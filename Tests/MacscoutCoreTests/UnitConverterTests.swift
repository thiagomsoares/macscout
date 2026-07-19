import Foundation
@testable import MacscoutCore

enum UnitConverterTests {
    static func mgdLFormatting() {
        checkEqual(UnitConverter.format(118, unit: .mgdL), "118")
        checkEqual(UnitConverter.format(118.4, unit: .mgdL), "118")
        checkEqual(UnitConverter.format(118.5, unit: .mgdL), "119")
    }

    static func mmolConversion() {
        checkEqual(UnitConverter.format(100, unit: .mmolL), "5.6")
        checkClose(UnitConverter.toUnit(180, .mmolL), 10.0)
        checkClose(UnitConverter.toMgdl(10.0, .mmolL), 180.0)
        checkClose(UnitConverter.toMgdl(UnitConverter.toUnit(72, .mmolL), .mmolL), 72)
    }

    static func mgdLIsIdentity() {
        checkEqual(UnitConverter.toUnit(137, .mgdL), 137)
        checkEqual(UnitConverter.toMgdl(137, .mgdL), 137)
    }

    static func deltaFormatting() {
        checkEqual(UnitConverter.formatDelta(-2, unit: .mgdL), "-2")
        checkEqual(UnitConverter.formatDelta(5, unit: .mgdL), "+5")
        checkEqual(UnitConverter.formatDelta(-1.8, unit: .mmolL), "-0.1")
        checkEqual(UnitConverter.formatDelta(1.8, unit: .mmolL), "+0.1")
    }

    static var tests: [(String, TestBody)] {
        [("mgdLFormatting", mgdLFormatting),
         ("mmolConversion", mmolConversion),
         ("mgdLIsIdentity", mgdLIsIdentity),
         ("deltaFormatting", deltaFormatting)]
    }
}
