import AppKit
import ServiceManagement
import SwiftUI
import MacscoutCore

/// View model driving the five onboarding acts.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var act = 1

    // Act 3 — Connect
    @Published var url: String
    @Published var token: String
    @Published var apiSecret: String
    @Published var testing = false
    @Published var testResult: ConnectionTestResult?
    @Published var demoChosen = false

    // Act 5 — ceremony
    @Published var ceremony = false

    var onFinish: (() -> Void)?

    let settings: SettingsStore
    let appState: AppState

    init(settings: SettingsStore, appState: AppState) {
        self.settings = settings
        self.appState = appState
        url = settings.siteURL
        token = settings.token
        apiSecret = settings.apiSecret
        // A previously working configuration stays one click away, but the
        // button press is still required (spec: test or demo before Next).
        demoChosen = settings.isDemoActive
    }

    enum ConnectionTestResult {
        case success(name: String, version: String?, entry: GlucoseEntry?, ageMinutes: Int?)
        case failure(String)
    }

    var canAdvance: Bool {
        act != 3 || testResult?.isSuccess == true || demoChosen
    }

    /// Transition direction for act changes.
    @Published var forward = true

    func next() {
        guard canAdvance, act < 5 else { return }
        forward = true
        withAnimation(.easeInOut(duration: 0.35)) { act += 1 }
    }

    func back() {
        guard act > 1, !ceremony else { return }
        forward = false
        withAnimation(.easeInOut(duration: 0.35)) { act -= 1 }
    }

    func skip() {
        onFinish?()
    }

    // MARK: Act 3

    func testConnection() {
        testing = true
        testResult = nil
        Task {
            let result = await Self.test(url: url, token: token, apiSecret: apiSecret)
            testResult = result
            testing = false
            if result.isSuccess {
                // Persist: URL via UserDefaults, secrets via Keychain; the
                // settings observers restart polling (a real refresh).
                settings.siteURL = url
                settings.token = token
                settings.apiSecret = apiSecret
                settings.demoMode = false
            }
        }
    }

    private static func test(url: String, token: String, apiSecret: String) async -> ConnectionTestResult {
        let client: NightscoutClient
        do {
            client = try NightscoutClient(baseURLString: url, token: token, apiSecret: apiSecret)
        } catch {
            return .failure(NightscoutError.invalidURL.localizedMessage)
        }
        do {
            let status = try await client.fetchServerStatus()
            let entries = try await client.fetchEntries(count: 1)
            let latest = entries.first
            let age = latest.map { max(0, Int(Date().timeIntervalSince($0.date) / 60)) }
            return .success(name: status.name ?? "nightscout",
                            version: status.version, entry: latest, ageMinutes: age)
        } catch let error as NightscoutError {
            return .failure(error.localizedMessage)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func continueWithDemo() {
        demoChosen = true
        settings.demoMode = true
    }

    // MARK: Act 5

    /// Ceremony: confetti, Glass sound, final glow pulse; close shortly after.
    func celebrate() {
        guard !ceremony else { return }
        ceremony = true
        appState.playCeremony()
        appState.pulseOnboardingGlow()
        appState.pillLanding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.onFinish?()
        }
    }
}

extension OnboardingModel.ConnectionTestResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Card view

/// Onboarding card: one subview per act inside the shared chrome.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                actContent
                    // Anchor content to the top so every act shares the same
                    // vertical rhythm (ceremonial acts center themselves).
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 48)
                    .padding(.top, 44)
                    .id(model.act)
                    .transition(.asymmetric(
                        insertion: .offset(y: model.forward ? 48 : -48).combined(with: .opacity),
                        removal: .opacity))
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            if model.ceremony {
                ConfettiView(trigger: model.ceremony)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 620, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.055, green: 0.055, blue: 0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.dsInRange.opacity(0.15), lineWidth: 1)
        )
        .tint(Color.dsInRange)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var actContent: some View {
        switch model.act {
        case 1: WelcomeAct()
        case 2: StoryAct()
        case 3: ConnectAct(model: model)
        case 4: AlertsAct(model: model)
        default: FinishAct(model: model)
        }
    }

    private var footer: some View {
        ZStack {
            ActProgressDots(current: model.act)
            HStack {
                Button(L("Skip")) { model.skip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(model.act == 5 || model.ceremony ? 0 : 1)
                Spacer()
                if model.act > 1 {
                    Button(L("Back")) { model.back() }
                }
                if model.act < 5 {
                    Button(L("Next")) { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canAdvance)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// Pixel-style act indicator: five squares, the current one stretches into a
/// phosphor bar.
private struct ActProgressDots: View {
    let current: Int // 1…5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { act in
                RoundedRectangle(cornerRadius: 1)
                    .fill(act == current ? Color.dsPhosphorBright : Color.white.opacity(0.28))
                    .frame(width: act == current ? 15 : 5, height: 5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: current)
        .accessibilityLabel(LF("Step %d of 5", current))
    }
}

/// Shared act header: small phosphor eyebrow + pixel title.
private struct ActHeader: View {
    let act: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LF("ACT %d OF 5", act))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.dsPhosphorDim)
            Text(title)
                .font(.pixel(22))
                .foregroundStyle(Color.dsPhosphorBright)
                .shadow(color: Color.dsPhosphorBright.opacity(0.45), radius: 4)
        }
    }
}

// MARK: - Act 1: Welcome

private struct WelcomeAct: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
                .shadow(color: Color.dsInRange.opacity(0.25), radius: 18)
            Text("Macscout")
                .font(.pixel(33))
                .foregroundStyle(Color.dsPhosphorBright)
                .shadow(color: Color.dsPhosphorBright.opacity(0.5), radius: 6)
                .padding(.top, 22)
            Text(L("Your Nightscout, in the notch."))
                .font(.title3.weight(.medium))
                .padding(.top, 12)
            Text(L("Live glucose, trend and alerts at the top of your screen — one glance, zero context switches."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                Text(L("That black band up there? It's already showing live demo data."))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.dsPhosphorBright)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.dsInRange.opacity(0.1), in: Capsule())
            .padding(.top, 26)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Act 2: Story

private struct StoryAct: View {
    private let beats: [(icon: String, color: Color, text: String)] = [
        ("arrow.triangle.2.circlepath", Color.dsHigh,
         L("You check your glucose dozens of times a day.")),
        ("iphone.slash", Color.dsAccent,
         L("Every check means grabbing your phone or switching apps — and losing focus.")),
        ("eye", Color.dsInRange,
         L("Macscout keeps it in the notch: one glance and you're back to work.")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActHeader(act: 2, title: L("Why the notch?"))
            VStack(alignment: .leading, spacing: 20) {
                ForEach(beats, id: \.text) { beat in
                    HStack(spacing: 14) {
                        Image(systemName: beat.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(beat.color)
                            .frame(width: 38, height: 38)
                            .background(beat.color.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(beat.text)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 34)

            // Live-demo callout, anchored to the brand drop.
            HStack(spacing: 10) {
                PulsingPixelIconView(color: Color.dsInRange)
                Text(L("The band up there is running on live demo data right now."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 30)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Act 3: Connect

private struct ConnectAct: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActHeader(act: 3, title: L("Connect your Nightscout"))
            Text(L("Paste your Nightscout site address. Token or API secret are only needed if your site requires authentication."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 10) {
                TextField("https://yoursite.example.com", text: $model.url)
                    .textFieldStyle(.roundedBorder)
                SecureField(L("Token (optional)"), text: $model.token)
                    .textFieldStyle(.roundedBorder)
                SecureField(L("API secret (optional)"), text: $model.apiSecret)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 22)

            HStack(spacing: 12) {
                Button(model.testing ? L("Testing…") : L("Test Connection")) {
                    model.testConnection()
                }
                .disabled(model.testing || model.url.isEmpty)

                resultView
            }
            .padding(.top, 14)

            demoRow
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
    }

    /// Phosphor-styled demo escape hatch, in the flow (not the footer).
    private var demoRow: some View {
        Button {
            model.continueWithDemo()
        } label: {
            HStack(spacing: 6) {
                if model.demoChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.dsInRange)
                    Text(L("Using demo data — you can continue"))
                        .foregroundStyle(Color.dsPhosphorBright)
                } else {
                    Text(L("No Nightscout yet? Continue with demo data"))
                        .foregroundStyle(Color.dsPhosphorBright)
                        .underline()
                }
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultView: some View {
        switch model.testResult {
        case .success(let name, let version, let entry, let age):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name)\(version.map { " · v\($0)" } ?? "")")
                        .font(.caption.weight(.semibold))
                    if let entry {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text(LF("Latest: %@ %@", UnitConverter.format(entry.sgv, unit: model.settings.unit), entry.direction.arrow))
                                .font(.caption.weight(.medium).monospacedDigit())
                            if let age {
                                Text(LF("· %d min ago", age))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        case .failure(let message):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Act 4: Alerts

private struct AlertsAct: View {
    @ObservedObject var model: OnboardingModel

    private var settings: SettingsStore { model.settings }
    private var unit: GlucoseUnit { settings.unit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActHeader(act: 4, title: L("Know when it matters"))
            Text(L("Recommended defaults, tuned to your unit. Adjust anytime."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            GroupBox {
                VStack(spacing: 8) {
                    row(L("Urgent low"), color: Color.dsUrgentLow,
                        keyPath: \.urgentLowThreshold, range: 30...90)
                    row(L("Low"), color: Color.dsLow,
                        keyPath: \.lowThreshold, range: 50...110)
                    row(L("High"), color: Color.dsHigh,
                        keyPath: \.highThreshold, range: 120...300)
                    row(L("Urgent high"), color: Color.dsUrgentHigh,
                        keyPath: \.urgentHighThreshold, range: 180...400)
                }
                .padding(6)
            }
            .padding(.top, 22)

            HStack {
                Button(L("Reset to recommended")) {
                    var alerts = settings.alertSettings
                    alerts.urgentLowThreshold = 55
                    alerts.lowThreshold = 70
                    alerts.highThreshold = 180
                    alerts.urgentHighThreshold = 250
                    settings.alertSettings = alerts
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.dsPhosphorBright)
                .underline()
                Spacer()
            }
            .padding(.top, 14)

            Text(L("Sounds, quiet hours and repeat intervals live in Settings → Alerts."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, color: Color,
                     keyPath: WritableKeyPath<AlertSettings, Double>,
                     range: ClosedRange<Double>) -> some View {
        let binding = Binding<Double>(
            get: { UnitConverter.toUnit(settings.alertSettings[keyPath: keyPath], unit) },
            set: { settings.alertSettings[keyPath: keyPath] = UnitConverter.toMgdl($0, unit) })
        // Bounds are authored in mg/dL; convert them to the display unit.
        let displayRange = UnitConverter.toUnit(range.lowerBound, unit)
            ... UnitConverter.toUnit(range.upperBound, unit)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 14)
            Text(label)
            Spacer()
            Stepper(value: binding, in: displayRange, step: UnitConverter.step(for: unit)) {
                Text(String(format: unit == .mmolL ? "%.1f" : "%.0f", binding.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - Act 5: Finish

private struct FinishAct: View {
    @ObservedObject var model: OnboardingModel

    private var settings: SettingsStore { model.settings }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.dsInRange)
                .shadow(color: Color.dsInRange.opacity(0.5), radius: 10)
            Text(L("One last thing"))
                .font(.pixel(22))
                .foregroundStyle(Color.dsPhosphorBright)
                .shadow(color: Color.dsPhosphorBright.opacity(0.45), radius: 4)
                .padding(.top, 18)
            Text(L("Two quick preferences and you're done."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 16) {
                Toggle(L("Launch Macscout at login"), isOn: launchAtLoginBinding)
                    .frame(maxWidth: 300)
                Picker(L("Units"), selection: Binding(
                    get: { settings.unit },
                    set: { settings.unit = $0 })) {
                    ForEach(GlucoseUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            .padding(.top, 28)

            Button(L("You're set")) {
                model.celebrate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.ceremony)
            .padding(.top, 32)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    settings.launchAtLogin = enable
                } catch {
                    NSLog("Macscout: launch-at-login failed: \(error.localizedDescription)")
                }
            })
    }
}

/// Fullscreen synthesized backdrop: blood-red rays fanning from top-center
/// over near-black, plus dim so the card pops. Drawn in code (Canvas).
struct RaysBackdropView: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.dsCanvas))

            let origin = CGPoint(x: size.width / 2, y: -size.height * 0.08)
            let radius = max(size.width, size.height) * 1.6
            let rayCount = 26
            for i in 0..<rayCount {
                // Fan across ~170° centered straight down.
                let centerAngle = Double.pi / 2
                let sweep = Double.pi * 0.95
                let a0 = centerAngle - sweep / 2 + sweep * Double(i) / Double(rayCount)
                let a1 = centerAngle - sweep / 2 + sweep * Double(i + 1) / Double(rayCount)
                // Angles here: 0 = +x, π/2 = -y (Canvas y-down); below uses sin/cos accordingly.
                var path = Path()
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + Foundation.cos(a0) * radius,
                                         y: origin.y + Foundation.sin(a0) * radius))
                path.addLine(to: CGPoint(x: origin.x + Foundation.cos(a1) * radius,
                                         y: origin.y + Foundation.sin(a1) * radius))
                path.closeSubpath()
                // Alternating ray intensity with a slight shimmer by index.
                let opacity = (i % 2 == 0 ? 0.16 : 0.07) * (0.7 + 0.3 * Foundation.sin(Double(i) * 1.7))
                context.fill(path, with: .color(.dsAccent.opacity(opacity)))
            }
        }
        // 60% dim (stronger toward the bottom) so the card pops.
        .overlay {
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
