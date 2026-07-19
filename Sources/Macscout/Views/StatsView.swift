import SwiftUI
import MacscoutCore

/// Time-in-range bar plus mean / GMI / reading count for the selected window.
struct StatsView: View {
    @ObservedObject var appState: AppState

    private var unit: GlucoseUnit { appState.settings.unit }

    var body: some View {
        if let stats = appState.stats {
            VStack(spacing: 8) {
                tirBar(stats)
                HStack(spacing: 0) {
                    stat(L("BELOW"), value: percent(stats.percentBelow), color: Color.dsUrgentLow)
                    stat(L("IN RANGE"), value: percent(stats.percentInRange), color: Color.dsInRange)
                    stat(L("ABOVE"), value: percent(stats.percentAbove), color: Color.dsHigh)
                    stat(L("MEAN"), value: UnitConverter.format(stats.meanMgdl, unit: unit), color: Color.dsPhosphorBright)
                    stat(L("GMI"), value: String(format: "%.1f%%", stats.gmi), color: Color.dsPhosphorBright)
                    stat(L("READINGS"), value: "\(stats.readingCount)", color: Color.dsPhosphorBright)
                }
            }
        } else {
            Text(LF("No data in the last %dh", appState.chartWindowHours))
                .font(.caption)
                .foregroundStyle(Color.dsPhosphorDim)
        }
    }

    /// Stacked time-in-range bar; range colors carry alert semantics here.
    private func tirBar(_ stats: GlucoseStats) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if stats.percentBelow > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.dsUrgentLow)
                        .frame(width: geo.size.width * stats.percentBelow / 100)
                }
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.dsInRange)
                    .frame(width: geo.size.width * stats.percentInRange / 100)
                if stats.percentAbove > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.dsHigh)
                        .frame(width: geo.size.width * stats.percentAbove / 100)
                }
            }
        }
        .frame(height: 6)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func stat(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.pixel(11))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Color.dsPhosphorDim.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}
