import Foundation

/// User-configurable alert categories.
public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case urgentLow, low, high, urgentHigh, risingFast, fallingFast, staleData

    public var displayName: String {
        switch self {
        case .urgentLow: return "Urgent Low"
        case .low: return "Low"
        case .high: return "High"
        case .urgentHigh: return "Urgent High"
        case .risingFast: return "Rising Fast"
        case .fallingFast: return "Falling Fast"
        case .staleData: return "Stale Data"
        }
    }

    /// Whether the alert represents an urgent condition (shorter cooldown, can auto-expand panel).
    public var isUrgent: Bool { self == .urgentLow || self == .urgentHigh }
}

/// Selectable alert sounds: the synthesized 8-bit cues (default) or the
/// bundled macOS system sounds.
public enum SystemSoundName: String, Codable, CaseIterable, Sendable {
    case chiptune = "8-bit (synthesized)"
    case none = "None", basso = "Basso", blow = "Blow", bottle = "Bottle",
         frog = "Frog", funk = "Funk", glass = "Glass", hero = "Hero",
         morse = "Morse", ping = "Ping", pop = "Pop", purr = "Purr",
         sosumi = "Sosumi", submarine = "Submarine", tink = "Tink"
}

/// Quiet hours window during which alert sounds are muted (visual alerts still fire).
/// The window may cross midnight (e.g. 22:00 → 07:00).
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    /// Minutes from midnight, local time. 0...1439
    public var fromMinutes: Int = 22 * 60
    public var toMinutes: Int = 7 * 60

    public init(enabled: Bool = false, fromMinutes: Int = 22 * 60, toMinutes: Int = 7 * 60) {
        self.enabled = enabled
        self.fromMinutes = fromMinutes
        self.toMinutes = toMinutes
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if fromMinutes <= toMinutes {
            return minutes >= fromMinutes && minutes < toMinutes
        } else {
            // Crosses midnight.
            return minutes >= fromMinutes || minutes < toMinutes
        }
    }
}

/// Full alert configuration. All glucose thresholds are stored in mg/dL.
public struct AlertSettings: Codable, Equatable, Sendable {
    public var urgentLowEnabled = true
    public var urgentLowThreshold: Double = 55
    public var urgentLowSound: SystemSoundName = .chiptune

    public var lowEnabled = true
    public var lowThreshold: Double = 70
    public var lowSound: SystemSoundName = .chiptune

    public var highEnabled = true
    public var highThreshold: Double = 180
    public var highSound: SystemSoundName = .chiptune

    public var urgentHighEnabled = true
    public var urgentHighThreshold: Double = 250
    public var urgentHighSound: SystemSoundName = .chiptune

    public var risingFastEnabled = false
    /// Delta (mg/dL per reading) that triggers "rising fast".
    public var risingFastDelta: Double = 5
    public var risingFastSound: SystemSoundName = .chiptune

    public var fallingFastEnabled = false
    /// Delta (mg/dL per reading) that triggers "falling fast".
    public var fallingFastDelta: Double = -5
    public var fallingFastSound: SystemSoundName = .chiptune

    public var staleDataEnabled = true
    /// Minutes without a new reading before data is considered stale.
    public var staleMinutes: Int = 10
    public var staleSound: SystemSoundName = .chiptune

    /// Global cooldown between repeated alerts of the same kind, in minutes.
    public var cooldownMinutes: Int = 20
    /// Cooldown for urgent alerts, in minutes.
    public var urgentCooldownMinutes: Int = 10

    /// Auto-expand the notch panel on urgent alerts.
    public var autoExpandOnUrgent = true

    public var quietHours = QuietHours()

    /// Alert volume 0.0–1.0.
    public var volume: Float = 0.8

    public init() {}

    public func isEnabled(_ kind: AlertKind) -> Bool {
        switch kind {
        case .urgentLow: return urgentLowEnabled
        case .low: return lowEnabled
        case .high: return highEnabled
        case .urgentHigh: return urgentHighEnabled
        case .risingFast: return risingFastEnabled
        case .fallingFast: return fallingFastEnabled
        case .staleData: return staleDataEnabled
        }
    }

    public func sound(for kind: AlertKind) -> SystemSoundName {
        switch kind {
        case .urgentLow: return urgentLowSound
        case .low: return lowSound
        case .high: return highSound
        case .urgentHigh: return urgentHighSound
        case .risingFast: return risingFastSound
        case .fallingFast: return fallingFastSound
        case .staleData: return staleSound
        }
    }
}
