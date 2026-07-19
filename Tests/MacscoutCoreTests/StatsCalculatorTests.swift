import Foundation
@testable import MacscoutCore

enum StatsCalculatorTests {
    static func entry(_ sgv: Double, at date: Date = Date()) -> GlucoseEntry {
        GlucoseEntry(id: UUID().uuidString, date: date, sgv: sgv, delta: nil, direction: .flat)
    }

    static func timeInRange() {
        let values: [Double] = [50, 80, 120, 150, 200, 70, 180, 90, 60, 250]
        let stats = unwrap(StatsCalculator.stats(for: values.map { entry($0) }, lowThreshold: 70, highThreshold: 180))
        checkClose(stats.percentInRange, 60, tolerance: 0.01)
        checkClose(stats.percentBelow, 20, tolerance: 0.01)
        checkClose(stats.percentAbove, 20, tolerance: 0.01)
        checkEqual(stats.readingCount, 10)
    }

    static func boundariesAreInclusive() {
        let stats = unwrap(StatsCalculator.stats(for: [entry(70), entry(180)], lowThreshold: 70, highThreshold: 180))
        checkClose(stats.percentInRange, 100, tolerance: 0.01)
    }

    static func meanAndGMI() {
        let stats = unwrap(StatsCalculator.stats(for: [entry(100), entry(120)], lowThreshold: 70, highThreshold: 180))
        checkClose(stats.meanMgdl, 110, tolerance: 0.01)
        // GMI = 3.31 + 0.02392 × 110 = 5.9412 → 5.9 (1 decimal)
        checkClose(stats.gmi, 5.9, tolerance: 0.05)
    }

    static func emptyReturnsNil() {
        check(StatsCalculator.stats(for: [], lowThreshold: 70, highThreshold: 180) == nil)
    }

    static func windowFilter() {
        let now = Date()
        let entries = [
            entry(100, at: now.addingTimeInterval(-3600)),
            entry(100, at: now.addingTimeInterval(-4 * 3600)),
            entry(100, at: now.addingTimeInterval(-30 * 3600)),
        ]
        checkEqual(StatsCalculator.entries(in: entries, hours: 3, now: now).count, 1)
        checkEqual(StatsCalculator.entries(in: entries, hours: 6, now: now).count, 2)
        checkEqual(StatsCalculator.entries(in: entries, hours: 24, now: now).count, 2)
    }

    static var tests: [(String, TestBody)] {
        [("timeInRange", timeInRange),
         ("boundariesAreInclusive", boundariesAreInclusive),
         ("meanAndGMI", meanAndGMI),
         ("emptyReturnsNil", emptyReturnsNil),
         ("windowFilter", windowFilter)]
    }
}
