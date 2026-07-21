import AppKit
import ServiceManagement
import SwiftUI
import MacscoutCore

/// Settings window (General / Alerts / Sounds / About tabs).
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updates: UpdateController

    /// Builds the settings NSWindow hosting this view.
    @MainActor
    static func makeWindow(appState: AppState, updates: UpdateController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = L("Macscout Settings")
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState, updates: updates))
        window.isReleasedWhenClosed = false
        return window
    }

    private var settings: SettingsStore { appState.settings }

    var body: some View {
        // Native settings layout: edge-to-edge tabs, no outer padding.
        TabView {
            GeneralTab(appState: appState, settings: appState.settings)
                .tabItem { Label(L("General"), systemImage: "gear") }
            AlertsTab(appState: appState, settings: appState.settings)
                .tabItem { Label(L("Alerts"), systemImage: "bell") }
            SoundsTab(appState: appState, settings: appState.settings)
                .tabItem { Label(L("Sounds"), systemImage: "speaker.wave.2") }
            AboutTab(appState: appState, updates: updates)
                .tabItem { Label(L("About"), systemImage: "info.circle") }
        }
        .frame(width: 500, height: 560)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore
    @State private var testResult: (ok: Bool, message: String)?
    @State private var testing = false

    // Write-through only on real change: the setters hit the Keychain and
    // restart polling, so echoing the same value back must stay a no-op.
    private var tokenBinding: Binding<String> {
        Binding(get: { settings.token },
                set: { if settings.token != $0 { settings.token = $0 } })
    }
    private var apiSecretBinding: Binding<String> {
        Binding(get: { settings.apiSecret },
                set: { if settings.apiSecret != $0 { settings.apiSecret = $0 } })
    }

    var body: some View {
        Form {
            Section("Nightscout") {
                TextField(L("Site URL"), text: $settings.siteURL, prompt: Text(verbatim: "https://yoursite.example.com"))
                SecureField(L("Token (optional)"), text: tokenBinding, prompt: Text(L("access token")))
                SecureField(L("API secret (optional)"), text: apiSecretBinding, prompt: Text(verbatim: "API_SECRET"))
                HStack {
                    Button(testing ? L("Testing…") : L("Test Connection")) {
                        testing = true
                        testResult = nil
                        Task {
                            let result = await appState.testConnection()
                            testResult = result
                            testing = false
                        }
                    }
                    .disabled(testing || settings.siteURL.isEmpty)
                    if let testResult {
                        Text(testResult.message)
                            .font(.caption)
                            .foregroundStyle(testResult.ok ? .green : .red)
                            .lineLimit(2)
                    }
                }
            }

            Section(L("Display")) {
                Picker(L("Language"), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker(L("Units"), selection: $settings.unit) {
                    ForEach(GlucoseUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker(L("Default chart window"), selection: $settings.chartWindowHours) {
                    ForEach([6, 12, 24], id: \.self) { Text(LF("%d hours", $0)).tag($0) }
                }
                Toggle(L("Show menu bar icon"), isOn: $settings.showMenuBarIcon)
            }

            Section(L("Behavior")) {
                Picker(L("Polling interval"), selection: $settings.pollingIntervalSeconds) {
                    Text(L("30 seconds")).tag(30)
                    Text(L("1 minute")).tag(60)
                    Text(L("2 minutes")).tag(120)
                    Text(L("5 minutes")).tag(300)
                }
                Toggle(L("Launch at login"), isOn: launchAtLoginBinding)
                Toggle(L("Expand notch on hover"), isOn: $settings.expandOnHover)
                Toggle(L("Demo mode"), isOn: $settings.demoMode)
            }
        }
        .formStyle(.grouped)
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
                    settings.launchAtLogin = false
                }
            })
    }
}

// MARK: - Alerts

private struct AlertsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore
    private var alerts: AlertSettings { settings.alertSettings }
    private var unit: GlucoseUnit { settings.unit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                alertGroups
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var alertGroups: some View {
                GroupBox(L("Glucose")) {
                    categoryRow(.urgentLow, enabled: binding(\.urgentLowEnabled),
                                value: glucoseBinding(\.urgentLowThreshold), range: 30...90,
                                sound: binding(\.urgentLowSound))
                    categoryRow(.low, enabled: binding(\.lowEnabled),
                                value: glucoseBinding(\.lowThreshold), range: 50...110,
                                sound: binding(\.lowSound))
                    categoryRow(.high, enabled: binding(\.highEnabled),
                                value: glucoseBinding(\.highThreshold), range: 120...300,
                                sound: binding(\.highSound))
                    categoryRow(.urgentHigh, enabled: binding(\.urgentHighEnabled),
                                value: glucoseBinding(\.urgentHighThreshold), range: 180...400,
                                sound: binding(\.urgentHighSound))
                }

                GroupBox(L("Rate of change")) {
                    categoryRow(.risingFast, enabled: binding(\.risingFastEnabled),
                                value: glucoseBinding(\.risingFastDelta), range: 1...20,
                                sound: binding(\.risingFastSound), label: "Δ ≥")
                    categoryRow(.fallingFast, enabled: binding(\.fallingFastEnabled),
                                value: glucoseBinding(\.fallingFastDelta), range: -20 ... -1,
                                sound: binding(\.fallingFastSound), label: "Δ ≤")
                }

                GroupBox(L("Stale data")) {
                    HStack {
                        Toggle(L("Stale Data"), isOn: binding(\.staleDataEnabled))
                        Spacer()
                        Stepper(LF("after %d min", alerts.staleMinutes),
                                value: binding(\.staleMinutes), in: 3...60)
                        soundPicker(binding(\.staleSound))
                    }
                }

                GroupBox(L("General")) {
                    Stepper(LF("Repeat alert every %d min", alerts.cooldownMinutes),
                            value: binding(\.cooldownMinutes), in: 1...120)
                    Stepper(LF("Repeat urgent every %d min", alerts.urgentCooldownMinutes),
                            value: binding(\.urgentCooldownMinutes), in: 1...60)
                    Toggle(L("Auto-expand panel on urgent alerts"), isOn: binding(\.autoExpandOnUrgent))
                    Toggle(L("Quiet hours (mute sounds only)"), isOn: binding(\.quietHours.enabled))
                    if alerts.quietHours.enabled {
                        HStack {
                            DatePicker(L("From"), selection: quietTimeBinding(\.quietHours.fromMinutes),
                                       displayedComponents: .hourAndMinute)
                            DatePicker(L("To"), selection: quietTimeBinding(\.quietHours.toMinutes),
                                       displayedComponents: .hourAndMinute)
                        }
                    }
                }
    }

    // MARK: Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<AlertSettings, T>) -> Binding<T> {
        Binding(get: { settings.alertSettings[keyPath: keyPath] },
                set: { settings.alertSettings[keyPath: keyPath] = $0 })
    }

    /// Threshold binding shown/edited in the user's unit, stored in mg/dL.
    private func glucoseBinding(_ keyPath: WritableKeyPath<AlertSettings, Double>) -> Binding<Double> {
        Binding(
            get: { UnitConverter.toUnit(settings.alertSettings[keyPath: keyPath], unit) },
            set: { settings.alertSettings[keyPath: keyPath] = UnitConverter.toMgdl($0, unit) })
    }

    private func quietTimeBinding(_ keyPath: WritableKeyPath<AlertSettings, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                let minutes = settings.alertSettings[keyPath: keyPath]
                return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1,
                                                          hour: minutes / 60, minute: minutes % 60))!
            },
            set: { date in
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                settings.alertSettings[keyPath: keyPath] = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            })
    }

    // MARK: Rows

    private func categoryRow(_ kind: AlertKind, enabled: Binding<Bool>, value: Binding<Double>,
                             range: ClosedRange<Double>, sound: Binding<SystemSoundName>,
                             label: String = L("at")) -> some View {
        // `range` is authored in mg/dL; the bound value is in display units —
        // convert the bounds too, or mmol/L users get clamped to mg/dL limits.
        let displayRange = UnitConverter.toUnit(range.lowerBound, unit)
            ... UnitConverter.toUnit(range.upperBound, unit)
        return HStack {
            Toggle(kind.localizedName, isOn: enabled)
                .frame(width: 130, alignment: .leading)
            Spacer()
            Text(label)
                .foregroundStyle(.secondary)
            Stepper(value: value, in: displayRange, step: UnitConverter.step(for: unit)) {
                Text(String(format: unit == .mmolL ? "%.1f" : "%.0f", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            soundPicker(sound)
        }
    }

    private func soundPicker(_ sound: Binding<SystemSoundName>) -> some View {
        Picker(L("Sound"), selection: sound) {
            ForEach(SystemSoundName.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 110)
    }
}

// MARK: - Sounds

private struct SoundsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(L("Volume")) {
                Slider(value: volumeBinding, in: 0...1) {
                    Text(L("Alert volume"))
                }
            }
            Section(L("Preview")) {
                ForEach(AlertKind.allCases, id: \.self) { kind in
                    HStack {
                        Text(kind.localizedName)
                        Spacer()
                        Text(L(settings.alertSettings.sound(for: kind).rawValue))
                            .foregroundStyle(.secondary)
                        Button(L("Play")) {
                            appState.previewSound(settings.alertSettings.sound(for: kind), for: kind)
                        }
                    }
                }
            }
            if settings.alertSettings.quietHours.enabled {
                Section {
                    Label(L("Quiet hours are on — sounds are muted, visual alerts still fire."),
                          systemImage: "moon.zzz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var volumeBinding: Binding<Float> {
        Binding(get: { settings.alertSettings.volume },
                set: { settings.alertSettings.volume = $0 })
    }
}

// MARK: - About

private struct AboutTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updates: UpdateController

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .padding(.top, 16)
                Text("Macscout")
                    .font(.title.bold())
                Text(LF("Version %@",
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
                    .foregroundStyle(.secondary)

                updateSection
                    .padding(.vertical, 4)

                Text(L("An open-source macOS notch / menu-bar client for Nightscout.\nNot affiliated with the Nightscout project."))
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L("Created by Thiago Mota Soares"))
                    .font(.callout.weight(.medium))
                Text(L("If Macscout helps you, a star on GitHub and a follow on Instagram make my day!"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 18) {
                    Link("⭐ github.com/thiagomsoares/macscout",
                         destination: URL(string: "https://github.com/thiagomsoares/macscout")!)
                    Link(L("@paipancreas on Instagram"),
                         destination: URL(string: "https://instagram.com/paipancreas")!)
                }
                .font(.callout)
                Button(L("Replay Onboarding…")) {
                    appState.settings.hasCompletedOnboarding = false
                    appState.onReplayOnboarding?()
                }
                .buttonStyle(.link)
                Text(L("Dedicated to the AndroidAPS community and to my son, George Benício Soares. ❤️"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                Text(L("MIT License · © Thiago Mota Soares and contributors"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Departure Mono font © Helena Zhang — SIL Open Font License 1.1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        VStack(spacing: 8) {
            switch updates.status {
            case .idle:
                Button(L("Check for Updates…")) {
                    Task { await updates.check() }
                }
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Checking for updates…"))
                        .foregroundStyle(.secondary)
                }
            case .upToDate(let current):
                Label(LF("You're up to date (%@)", current), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Button(L("Check Again")) {
                    Task { await updates.check() }
                }
                .buttonStyle(.link)
            case .available(let version, _, _, let dmgName, let bytes):
                VStack(spacing: 6) {
                    Label(LF("Macscout %@ is available", version), systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(LF("Download %@ (%@) to your Downloads folder.",
                            dmgName, UpdateController.formatBytes(bytes)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button(L("Download")) {
                            Task { await updates.download() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(L("View Release")) { updates.openReleasePage() }
                            .buttonStyle(.link)
                    }
                }
                .padding(12)
                .frame(maxWidth: 360)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Downloading…"))
                        .foregroundStyle(.secondary)
                }
            case .downloaded(let fileURL):
                VStack(spacing: 6) {
                    Label(L("Download complete"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.semibold))
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L("Open the DMG and drag Macscout into Applications."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(L("Open DMG")) { updates.openDownloaded() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed(let message):
                VStack(spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button(L("Try Again")) {
                        Task { await updates.check() }
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .frame(minHeight: 36)
    }
}
