import SwiftUI
import MacscoutCore

/// Miniature glucose trail for the collapsed band, in the same pixel language
/// as the panel chart: one dot per time column at the reading's height,
/// fading with age, with a brighter tip for the latest reading. Fixed 12 h
/// window (a full half-day at a glance). Pure Canvas.
struct SparklineView: View {
    let entries: [GlucoseEntry] // newest-first (AppState.entries)
    let alertSettings: AlertSettings
    var window: TimeInterval = 12 * 3600

    private let pitch: CGFloat = 2.6
    private let dotR: CGFloat = 1.1

    private var trace: Color { Color.dsInRange }

    var body: some View {
        Canvas { context, size in
            let now = Date()
            let start = now.addingTimeInterval(-window)
            let pts = Array(entries.filter { $0.date >= start }.reversed()) // oldest-first
            guard pts.count > 1 else { return }
            let values = pts.map(\.sgv)
            let lo = min(values.min()!, alertSettings.lowThreshold)
            let hi = max(values.max()!, alertSettings.highThreshold)
            let span = max(hi - lo, 1)
            let inset = dotR + 1.5

            func y(_ sgv: Double) -> CGFloat {
                size.height - inset - CGFloat((sgv - lo) / span) * (size.height - inset * 2)
            }

            // One dot per column, nearest reading; empty cells stay empty.
            let cols = max(Int(size.width / pitch), 2)
            let cellSpan = window / Double(cols)
            var i = 0
            for c in 0..<cols {
                let t = start.addingTimeInterval((Double(c) + 0.5) * cellSpan)
                while i + 1 < pts.count,
                      abs(pts[i + 1].date.timeIntervalSince(t)) <= abs(pts[i].date.timeIntervalSince(t)) {
                    i += 1
                }
                let nearest = pts[i]
                guard abs(nearest.date.timeIntervalSince(t)) <= max(cellSpan / 2, 600) else { continue }
                let x = (CGFloat(c) + 0.5) * pitch
                let alpha = 0.35 + 0.65 * Double(c) / Double(cols - 1)
                let rect = CGRect(x: x - dotR, y: y(nearest.sgv) - dotR,
                                  width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: rect), with: .color(trace.opacity(alpha)))
            }

            // Latest reading: brighter, slightly larger tip at the right edge.
            if let latest = pts.last {
                let r: CGFloat = 1.8
                let rect = CGRect(x: size.width - r * 2 - 0.5, y: y(latest.sgv) - r,
                                  width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}
