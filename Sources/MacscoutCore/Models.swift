import Foundation

/// Glucose display unit.
public enum GlucoseUnit: String, Codable, CaseIterable, Sendable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
}

/// Glucose trend direction as reported by Nightscout `direction` values.
public enum TrendArrow: String, Codable, Sendable, CaseIterable {
    case doubleUp = "DoubleUp"
    case singleUp = "SingleUp"
    case fortyFiveUp = "FortyFiveUp"
    case flat = "Flat"
    case fortyFiveDown = "FortyFiveDown"
    case singleDown = "SingleDown"
    case doubleDown = "DoubleDown"
    case notComputable = "NOT COMPUTABLE"
    case none = "NONE"
    case rateOutOfRange = "RateOutOfRange"

    /// Glyph shown in the UI, matching Nightscout conventions.
    public var arrow: String {
        switch self {
        case .doubleUp: return "↑↑"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "↓↓"
        case .notComputable, .none: return "–"
        case .rateOutOfRange: return "⚠︎"
        }
    }

    /// VoiceOver / accessibility description.
    public var accessibilityLabel: String {
        switch self {
        case .doubleUp: return "rising rapidly"
        case .singleUp: return "rising"
        case .fortyFiveUp: return "rising slowly"
        case .flat: return "steady"
        case .fortyFiveDown: return "falling slowly"
        case .singleDown: return "falling"
        case .doubleDown: return "falling rapidly"
        case .notComputable, .none: return "trend unavailable"
        case .rateOutOfRange: return "rate out of range"
        }
    }
}

/// A single sensor glucose value from `/api/v1/entries.json`.
/// `sgv` is always in mg/dL as returned by Nightscout.
public struct GlucoseEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let sgv: Double
    /// Per-reading delta in mg/dL (may be absent).
    public let delta: Double?
    public let direction: TrendArrow
    public let device: String?

    public init(id: String, date: Date, sgv: Double, delta: Double?, direction: TrendArrow, device: String? = nil) {
        self.id = id
        self.date = date
        self.sgv = sgv
        self.delta = delta
        self.direction = direction
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case date, sgv, delta, direction, device
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sgv = try c.decodeIfPresent(Double.self, forKey: .sgv)
            ?? c.decodeIfPresent(Int.self, forKey: .sgv).map(Double.init)
            ?? 0
        delta = try c.decodeIfPresent(Double.self, forKey: .delta)
        direction = (try? c.decode(TrendArrow.self, forKey: .direction)) ?? .none
        device = try c.decodeIfPresent(String.self, forKey: .device)
        if let ms = try c.decodeIfPresent(Double.self, forKey: .date) {
            date = Date(timeIntervalSince1970: ms / 1000)
        } else {
            let str = try c.decode(String.self, forKey: .date)
            guard let parsed = Self.isoFormatter.date(from: str) else {
                throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Bad date \(str)")
            }
            date = parsed
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// A treatment record (carbs, insulin, etc.) from `/api/v1/treatments.json`.
public struct Treatment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let eventType: String?
    public let carbs: Double?
    public let insulin: Double?

    public init(id: String, createdAt: Date, eventType: String? = nil, carbs: Double? = nil, insulin: Double? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.eventType = eventType
        self.carbs = carbs
        self.insulin = insulin
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case eventType, carbs, insulin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs)
        insulin = try c.decodeIfPresent(Double.self, forKey: .insulin)
        let str = try c.decode(String.self, forKey: .createdAt)
        if let d = Self.isoFractional.date(from: str) ?? Self.isoPlain.date(from: str) {
            createdAt = d
        } else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: c, debugDescription: "Bad created_at \(str)")
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
}

/// Uploader device status from `/api/v1/devicestatus.json` (optional display).
public struct DeviceStatus: Codable, Equatable, Sendable {
    public let createdAt: Date?
    public let uploaderBattery: Int?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case uploader
    }
    struct Uploader: Codable, Equatable {
        let battery: Int?
    }
    private let uploader: Uploader?

    public init(createdAt: Date?, uploaderBattery: Int?) {
        self.createdAt = createdAt
        self.uploaderBattery = uploaderBattery
        self.uploader = Uploader(battery: uploaderBattery)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uploader = try c.decodeIfPresent(Uploader.self, forKey: .uploader)
        uploaderBattery = uploader?.battery
        if let str = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = f.date(from: str) ?? ISO8601DateFormatter().date(from: str)
        } else {
            createdAt = nil
        }
    }
}

/// Server status from `/api/v1/status.json`, used by "Test Connection".
public struct NightscoutServerStatus: Codable, Equatable, Sendable {
    public let status: String
    public let name: String?
    public let version: String?
    public let apiEnabled: Bool?
}
