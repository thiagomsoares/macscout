import Foundation
import MacscoutCore

/// App display language. Raw values are persisted in settings.
enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case portugueseBR = "pt-BR"

    /// Picker label — each language names itself; "System" localizes.
    var displayName: String {
        switch self {
        case .system: return L("System")
        case .english: return "English"
        case .portugueseBR: return "Português (Brasil)"
        }
    }
}

/// Tiny live-switchable localization. Keys are the English copy, so English
/// needs no table and missing translations fall back gracefully; other
/// languages live in `Resources/<code>.lproj/Localizable.strings`. Switching
/// swaps the bundle and the AppDelegate rebuilds the visible surfaces.
enum L10n {
    private(set) static var bundle: Bundle?

    static func apply(_ language: AppLanguage) {
        let code: String?
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            code = preferred.hasPrefix("pt") ? "pt-BR" : nil
        case .english:
            code = nil
        case .portugueseBR:
            code = "pt-BR"
        }
        if let code,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localized = Bundle(path: path) {
            bundle = localized
        } else {
            bundle = nil // English — the keys themselves are the copy
        }
    }
}

/// Localized copy for `key` (the key is the English text).
func L(_ key: String) -> String {
    L10n.bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
}

/// Format-string variant: `LF("%d min ago", 3)`.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

extension AlertKind {
    /// Localized display name (Core's `displayName` is the English source).
    var localizedName: String { L(displayName) }
}

extension AlertEvent {
    /// Localized, unit-aware message (Core's `message` is fixed English mg/dL).
    func localizedMessage(unit: GlucoseUnit) -> String {
        switch kind {
        case .urgentLow:
            return LF("Urgent low: %@ %@", UnitConverter.format(value, unit: unit), unit.rawValue)
        case .low:
            return LF("Low: %@ %@", UnitConverter.format(value, unit: unit), unit.rawValue)
        case .high:
            return LF("High: %@ %@", UnitConverter.format(value, unit: unit), unit.rawValue)
        case .urgentHigh:
            return LF("Urgent high: %@ %@", UnitConverter.format(value, unit: unit), unit.rawValue)
        case .risingFast:
            return LF("Rising fast: %@ %@", UnitConverter.formatDelta(value, unit: unit), unit.rawValue)
        case .fallingFast:
            return LF("Falling fast: %@ %@", UnitConverter.formatDelta(value, unit: unit), unit.rawValue)
        case .staleData:
            return LF("No new data for %d min", Int(value))
        }
    }
}

extension NightscoutError {
    /// Localized user-facing description (Core's is fixed English).
    var localizedMessage: String {
        switch self {
        case .invalidURL: return L("Invalid Nightscout URL.")
        case .unauthorized: return L("Unauthorized — check token / api-secret.")
        case .httpError(let code): return LF("Server returned HTTP %d.", code)
        case .decoding: return L("Unexpected response format.")
        case .network(let detail): return detail
        }
    }
}
