import Foundation

/// Conversion and formatting between mg/dL and mmol/L.
/// Nightscout stores/returns mg/dL; mmol/L = mg/dL ÷ 18.018 (≈ ÷ 18).
public enum UnitConverter {
    public static let mmolFactor = 18.0

    public static func toUnit(_ mgdl: Double, _ unit: GlucoseUnit) -> Double {
        unit == .mmolL ? mgdl / mmolFactor : mgdl
    }

    public static func toMgdl(_ value: Double, _ unit: GlucoseUnit) -> Double {
        unit == .mmolL ? value * mmolFactor : value
    }

    /// Formatted glucose value in the given unit (0 decimals mg/dL, 1 decimal mmol/L).
    public static func format(_ mgdl: Double, unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdL:
            return String(format: "%.0f", mgdl.rounded())
        case .mmolL:
            return String(format: "%.1f", toUnit(mgdl, .mmolL))
        }
    }

    /// Formatted per-reading delta, always signed.
    public static func formatDelta(_ mgdlDelta: Double, unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdL:
            return String(format: "%+.0f", mgdlDelta)
        case .mmolL:
            return String(format: "%+.1f", toUnit(mgdlDelta, .mmolL))
        }
    }

    /// Step size appropriate for threshold steppers in the given unit.
    public static func step(for unit: GlucoseUnit) -> Double {
        unit == .mmolL ? 0.1 : 1.0
    }
}
