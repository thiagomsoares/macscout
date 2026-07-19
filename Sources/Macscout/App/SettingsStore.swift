import Combine
import Foundation
import Security
import MacscoutCore

/// UserDefaults-backed app settings; secrets (token / api-secret) live in the
/// Keychain. All access is main-thread (app is a single-window agent).
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Fires when secrets change or a reload of the polling loop is needed.
    let reloadRequested = PassthroughSubject<Void, Never>()

    enum Key: String {
        case siteURL, unit, pollingIntervalSeconds, chartWindowHours
        case launchAtLogin, showMenuBarIcon, demoMode, hasCompletedOnboarding, expandOnHover
        case appLanguage
    }

    /// UI language: follow the system, English, or Português (Brasil).
    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Key.appLanguage.rawValue) }
    }

    @Published var siteURL: String {
        didSet { defaults.set(siteURL, forKey: Key.siteURL.rawValue) }
    }
    @Published var unit: GlucoseUnit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit.rawValue) }
    }
    /// Seconds between polls; one of 30 / 60 / 120 / 300.
    @Published var pollingIntervalSeconds: Int {
        didSet { defaults.set(pollingIntervalSeconds, forKey: Key.pollingIntervalSeconds.rawValue) }
    }
    /// Default chart window in hours; one of 6 / 12 / 24 (6 h minimum).
    @Published var chartWindowHours: Int {
        didSet { defaults.set(chartWindowHours, forKey: Key.chartWindowHours.rawValue) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon.rawValue) }
    }
    @Published var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode.rawValue) }
    }
    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover.rawValue) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding.rawValue) }
    }
    @Published var alertSettings: AlertSettings {
        didSet {
            if let data = try? JSONEncoder().encode(alertSettings) {
                defaults.set(data, forKey: "alertSettings")
            }
        }
    }

    init() {
        siteURL = defaults.string(forKey: Key.siteURL.rawValue) ?? ""
        unit = GlucoseUnit(rawValue: defaults.string(forKey: Key.unit.rawValue) ?? "") ?? .mgdL
        let interval = defaults.integer(forKey: Key.pollingIntervalSeconds.rawValue)
        pollingIntervalSeconds = interval > 0 ? interval : 60
        // 6 h floor (migrates the old 3 h option to 6 h).
        let window = defaults.integer(forKey: Key.chartWindowHours.rawValue)
        chartWindowHours = window >= 6 ? window : 6
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon.rawValue) as? Bool ?? true
        demoMode = defaults.bool(forKey: Key.demoMode.rawValue)
        expandOnHover = defaults.object(forKey: Key.expandOnHover.rawValue) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue)
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage.rawValue) ?? "") ?? .system
        if let data = defaults.data(forKey: "alertSettings"),
           let decoded = try? JSONDecoder().decode(AlertSettings.self, from: data) {
            alertSettings = decoded
        } else {
            alertSettings = AlertSettings()
        }
    }

    // MARK: - Secrets (Keychain)

    var token: String {
        get { Keychain.read(account: "token") ?? "" }
        set { Keychain.store(newValue, account: "token"); reloadRequested.send() }
    }
    var apiSecret: String {
        get { Keychain.read(account: "apiSecret") ?? "" }
        set { Keychain.store(newValue, account: "apiSecret"); reloadRequested.send() }
    }

    /// Demo mode is also active when no site URL is configured.
    var isDemoActive: Bool {
        demoMode || siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Builds a client for the configured site, or nil when the URL is invalid.
    func makeClient() -> NightscoutClient? {
        try? NightscoutClient(baseURLString: siteURL, token: token, apiSecret: apiSecret)
    }
}

/// Minimal Keychain wrapper for generic-password string items.
enum Keychain {
    private static let service = "app.macscout.macos"

    static func store(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return }
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
