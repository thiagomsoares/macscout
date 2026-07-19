import Foundation

/// Aggregate statistics for a window of glucose readings.
public struct GlucoseStats: Equatable, Sendable {
    /// Percentage of readings below the low threshold (0–100).
    public let percentBelow: Double
    /// Percentage of readings in range (0–100).
    public let percentInRange: Double
    /// Percentage of readings above the high threshold (0–100).
    public let percentAbove: Double
    /// Mean glucose in mg/dL.
    public let meanMgdl: Double
    /// Glucose Management Indicator: 3.31 + 0.02392 × mean(mg/dL).
    public let gmi: Double
    public let readingCount: Int
}

/// Computes time-in-range and related stats. Thresholds are in mg/dL.
public enum StatsCalculator {
    /// - In range: `lowThreshold ≤ sgv ≤ highThreshold`.
    /// - Returns nil when the window contains no readings.
    public static func stats(for entries: [GlucoseEntry], lowThreshold: Double, highThreshold: Double) -> GlucoseStats? {
        guard !entries.isEmpty else { return nil }
        let total = Double(entries.count)
        var below = 0.0, inRange = 0.0, above = 0.0, sum = 0.0
        for e in entries {
            sum += e.sgv
            if e.sgv < lowThreshold { below += 1 }
            else if e.sgv > highThreshold { above += 1 }
            else { inRange += 1 }
        }
        let mean = sum / total
        let gmi = 3.31 + 0.02392 * mean
        return GlucoseStats(
            percentBelow: below / total * 100,
            percentInRange: inRange / total * 100,
            percentAbove: above / total * 100,
            meanMgdl: mean,
            gmi: (gmi * 10).rounded() / 10,
            readingCount: entries.count
        )
    }

    /// Filter entries to the trailing `hours` window relative to `now`.
    public static func entries(in entries: [GlucoseEntry], hours: Int, now: Date = Date()) -> [GlucoseEntry] {
        let cutoff = now.addingTimeInterval(-TimeInterval(hours) * 3600)
        return entries.filter { $0.date >= cutoff }
    }
}
