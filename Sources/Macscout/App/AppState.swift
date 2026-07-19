import AppKit
import Combine
import MacscoutCore

/// Connection state shown in the UI.
enum ConnectionStatus: Equatable {
    case ok
    case connecting
    case error(String)
    case demo
}

/// Central UI state: polling loop, latest data, alerts, and demo mode.
@MainActor
final class AppState: ObservableObject {
    // MARK: Published UI state

    @Published private(set) var currentEntry: GlucoseEntry?
    /// Newest-first entries covering the trailing 24 h (fewer in demo warmup).
    @Published private(set) var entries: [GlucoseEntry] = [] {
        didSet { cachedChartEntries = nil }
    }
    @Published private(set) var treatments: [Treatment] = []
    @Published private(set) var deviceStatus: DeviceStatus?
    @Published private(set) var status: ConnectionStatus = .connecting
    @Published private(set) var activeAlert: AlertEvent?
    @Published private(set) var lastUpdated: Date?
    /// Selected chart window in hours (3/6/12/24); defaults from settings.
    @Published var chartWindowHours: Int {
        didSet { cachedChartEntries = nil }
    }

    /// Called on urgent alerts (to auto-expand the panel).
    var onUrgentAlert: (() -> Void)?
    /// Called when menu-bar/panel visibility settings change.
    var onVisibilityChanged: (() -> Void)?
    /// Called from the panel's Settings button.
    var onOpenSettings: (() -> Void)?
    /// Called from Settings → About "Replay Onboarding…".
    var onReplayOnboarding: (() -> Void)?

    /// Drives the animated glow around the notch pill (onboarding).
    @Published var onboardingGlow = false
    /// Brief intensified glow pulse (onboarding ceremony).
    @Published var onboardingGlowPulse = false
    /// Pill "landing bounce" trigger (onboarding ceremony).
    @Published var pillLanding = false

    let settings: SettingsStore
    private let alertEngine = AlertEngine()
    private let soundPlayer = SoundPlayer()
    private lazy var notifier = AlertNotifier()
    private var pollTask: Task<Void, Never>?
    private var demoGenerator: DemoDataGenerator?

    /// Entry-count ceiling for the 24 h window fetch. The window itself is
    /// enforced server-side (`since`); the count only caps pathological
    /// high-frequency uploaders (1-min AID rigs need ~1440).
    private let fetchCount = 3000

    init(settings: SettingsStore) {
        self.settings = settings
        self.chartWindowHours = settings.chartWindowHours

        // Restart polling (debounced) when connection-relevant settings change.
        let critical = settings.$siteURL.map { _ in () }
            .merge(with: settings.$demoMode.map { _ in () },
                   settings.$pollingIntervalSeconds.map { _ in () },
                   settings.reloadRequested)
        critical
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }
            .store(in: &cancellables)

        // @Published emits in willSet — deliver on the next runloop turn so
        // the handler reads the NEW value (otherwise hiding the menu bar
        // icon is a no-op: updateVisibility still sees the old setting).
        settings.$showMenuBarIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.onVisibilityChanged?() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    deinit { pollTask?.cancel() }

    // MARK: - Polling

    func start() {
        restart()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Restarts the polling loop (e.g. after settings changes).
    func restart() {
        stop()
        alertEngine.reset()
        if settings.isDemoActive {
            demoGenerator = DemoDataGenerator()
            status = .demo
        } else {
            demoGenerator = nil
            status = .connecting
        }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.tick(fetch: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                let needsFetch = self.lastUpdated == nil
                    || Date().timeIntervalSince(self.lastUpdated!) >= Double(self.settings.pollingIntervalSeconds)
                await self.tick(fetch: needsFetch)
            }
        }
    }

    /// Single refresh (menu "Refresh" / panel button).
    func refresh() {
        Task { await tick(fetch: true) }
    }

    private func tick(fetch: Bool) async {
        if var demo = demoGenerator {
            demo.advance(to: Date())
            demoGenerator = demo
            entries = demo.entries
            treatments = demo.treatments
            currentEntry = demo.entries.first
            lastUpdated = Date()
            status = .demo
            evaluateAlerts()
            return
        }

        guard let client = settings.makeClient() else {
            status = .error(L("Invalid Nightscout URL — open Settings."))
            return
        }
        if fetch {
            do {
                async let fetchedEntries = client.fetchEntries(
                    count: fetchCount, since: Date().addingTimeInterval(-24 * 3600))
                async let fetchedTreatments = client.fetchTreatments(
                    since: Date().addingTimeInterval(-24 * 3600))
                let (newEntries, newTreatments) = try await (fetchedEntries, fetchedTreatments)
                entries = newEntries.sorted { $0.date > $1.date }
                treatments = newTreatments.sorted { $0.createdAt > $1.createdAt }
                currentEntry = entries.first
                lastUpdated = Date()
                status = .ok
            } catch let error as NightscoutError {
                status = .error(error.localizedMessage)
            } catch {
                status = .error(error.localizedDescription)
            }
            // Device status is optional; failures are non-fatal.
            deviceStatus = try? await client.fetchDeviceStatus()
        }
        evaluateAlerts()
    }

    // MARK: - Alerts

    private func evaluateAlerts() {
        let events = alertEngine.evaluate(entries: entries, settings: settings.alertSettings)
        guard let event = events.first else { return }
        activeAlert = event
        let quiet = alertEngine.inQuietHours(settings: settings.alertSettings)
        soundPlayer.play(settings.alertSettings.sound(for: event.kind), for: event.kind,
                         volume: settings.alertSettings.volume, muted: quiet)
        notifier.post(event, unit: settings.unit)
        if event.kind.isUrgent, settings.alertSettings.autoExpandOnUrgent {
            onUrgentAlert?()
        }
    }

    func dismissAlert() {
        activeAlert = nil
    }

    // MARK: - Display helpers

    var isDemo: Bool { demoGenerator != nil }

    /// Latest data age in whole minutes.
    var dataAgeMinutes: Int? {
        guard let date = currentEntry?.date else { return nil }
        return max(0, Int(Date().timeIntervalSince(date) / 60))
    }

    var isStale: Bool {
        guard let age = dataAgeMinutes else { return false }
        return age >= settings.alertSettings.staleMinutes
    }

    /// Nightscout-style color for the current value (gray when stale).
    var currentColor: NSColor {
        Self.color(for: currentEntry?.sgv, settings: settings.alertSettings, stale: isStale)
    }

    static func color(for sgv: Double?, settings: AlertSettings, stale: Bool = false) -> NSColor {
        // Design tokens (docs/DESIGN.md); Nightscout semantics preserved.
        guard let sgv, !stale else { return DSColors.stale }
        if sgv <= settings.urgentLowThreshold { return DSColors.urgentLow }
        if sgv < settings.lowThreshold { return DSColors.low }
        if sgv >= settings.urgentHighThreshold { return DSColors.urgentHigh }
        if sgv > settings.highThreshold { return DSColors.high }
        return DSColors.inRange
    }

    var displayValue: String {
        guard let entry = currentEntry else { return "–" }
        return UnitConverter.format(entry.sgv, unit: settings.unit)
    }

    var displayDelta: String {
        guard let delta = currentEntry?.delta else { return "" }
        return UnitConverter.formatDelta(delta, unit: settings.unit)
    }

    var displayArrow: String {
        currentEntry?.direction.arrow ?? ""
    }

    /// Compact "118 ↗" used by the menu bar item and collapsed pill.
    var menuBarText: String {
        if isStale { return "\(displayValue) !" }
        return "\(displayValue) \(displayArrow)"
    }

    var tooltipText: String {
        if let age = dataAgeMinutes {
            return LF("%d min ago · Macscout", age)
        }
        return "Macscout"
    }

    /// Memoized `chartEntries`; invalidated when entries or the window change.
    private var cachedChartEntries: [GlucoseEntry]?

    /// Entries within the selected chart window, oldest first (for the chart
    /// and sparkline). Filtering + sorting are memoized — SwiftUI reads this
    /// on every render, including pointer-driven ones.
    var chartEntries: [GlucoseEntry] {
        if let cachedChartEntries { return cachedChartEntries }
        let computed = StatsCalculator.entries(in: entries, hours: chartWindowHours)
            .sorted { $0.date < $1.date }
        cachedChartEntries = computed
        return computed
    }

    var chartTreatments: [Treatment] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(chartWindowHours) * 3600)
        return treatments.filter { $0.createdAt >= cutoff }
    }

    var stats: GlucoseStats? {
        StatsCalculator.stats(for: chartEntries,
                              lowThreshold: settings.alertSettings.lowThreshold,
                              highThreshold: settings.alertSettings.highThreshold)
    }

    // MARK: - Settings actions

    /// Result of a settings "Test Connection" tap.
    func testConnection() async -> (ok: Bool, message: String) {
        guard let client = settings.makeClient() else {
            return (false, L("Invalid URL — use http(s)://host"))
        }
        do {
            let status = try await client.fetchServerStatus()
            let version = status.version.map { " · v\($0)" } ?? ""
            return (true, LF("Connected%@", version))
        } catch let error as NightscoutError {
            return (false, error.localizedMessage)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func previewSound(_ sound: SystemSoundName, for kind: AlertKind) {
        soundPlayer.play(sound, for: kind, volume: settings.alertSettings.volume, muted: false)
    }

    /// Onboarding ceremony jingle.
    func playCeremony() {
        soundPlayer.playCeremony(volume: settings.alertSettings.volume)
    }

    /// Single glow pulse on the notch pill (used by the onboarding ceremony).
    func pulseOnboardingGlow() {
        onboardingGlowPulse = true
    }
}

// MARK: - Demo data

/// Synthetic CGM data: sine wave (~3 h period) around 120 mg/dL plus noise,
/// one point per simulated 5 minutes, occasional carb/insulin treatments.
struct DemoDataGenerator {
    private(set) var entries: [GlucoseEntry] = []
    private(set) var treatments: [Treatment] = []
    private var lastSimulated: Date

    init(now: Date = Date()) {
        lastSimulated = now.addingTimeInterval(-12 * 3600)
        advance(to: now)
    }

    private static func sgv(at date: Date) -> Double {
        let t = date.timeIntervalSince1970
        let wave = sin(t / (3 * 3600) * 2 * .pi) * 45
        let noise = Double.random(in: -4...4)
        return (120 + wave + noise).rounded()
    }

    /// Extends the simulated timeline up to `now`, adding a point per 5 min.
    mutating func advance(to now: Date) {
        var cursor = lastSimulated
        while cursor <= now {
            let sgv = Self.sgv(at: cursor)
            let delta = entries.first.map { sgv - $0.sgv }
            let entry = GlucoseEntry(
                id: "demo-\(Int(cursor.timeIntervalSince1970))",
                date: cursor, sgv: sgv, delta: delta,
                direction: Self.direction(for: delta ?? 0), device: "Macscout Demo")
            entries.insert(entry, at: 0)

            // Occasional treatments (~every couple of hours on average).
            if Int(cursor.timeIntervalSince1970 / 300) % 23 == 0 {
                let carb = Bool.random()
                treatments.insert(Treatment(
                    id: "demo-t-\(Int(cursor.timeIntervalSince1970))",
                    createdAt: cursor,
                    eventType: carb ? "Carb Correction" : "Correction Bolus",
                    carbs: carb ? Double([15, 20, 30, 45].randomElement()!) : nil,
                    insulin: carb ? nil : Double([1, 2, 3].randomElement()!)), at: 0)
            }
            cursor += 300
        }
        lastSimulated = cursor - 300
        // Keep the trailing 24 h only.
        let cutoff = now.addingTimeInterval(-24 * 3600)
        entries.removeAll { $0.date < cutoff }
        treatments.removeAll { $0.createdAt < cutoff }
    }

    private static func direction(for delta: Double) -> TrendArrow {
        switch delta {
        case 6...: return .singleUp
        case 3..<6: return .fortyFiveUp
        case -3..<3: return .flat
        case -6 ..< -3: return .fortyFiveDown
        default: return .singleDown
        }
    }
}
