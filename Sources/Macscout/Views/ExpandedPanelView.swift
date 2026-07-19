import SwiftUI
import MacscoutCore

/// Expanded dashboard: header, chart, stats, window picker, actions.
struct ExpandedPanelView: View {
    @ObservedObject var appState: AppState
    @State private var appeared = false

    private let windowOptions = [6, 12, 24]
    /// Same contour family as the collapsed band: concave top ears melting
    /// out of the menu bar, generous convex bottom corners.
    private let panelShape = NotchBandShape(topCornerRadius: 6, bottomCornerRadius: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .risesIn(appeared, beat: 0)
            if let alert = appState.activeAlert {
                alertBanner(alert)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if case .error(let message) = appState.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.dsLow)
                    .lineLimit(2)
            }
            GlucoseChartView(appState: appState)
                .frame(minHeight: 150, maxHeight: .infinity)
                .risesIn(appeared, beat: 1)
            StatsView(appState: appState)
                .risesIn(appeared, beat: 2)
            footer
                .risesIn(appeared, beat: 3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.25), value: appState.activeAlert)
        // Same chrome as the collapsed band: pure black, faint white hairline
        // along the notch contour.
        .background(.black, in: panelShape)
        .overlay(CRTScreenEffect())
        .overlay(panelShape.stroke(.white.opacity(0.12), lineWidth: 1))
        .clipShape(panelShape)
        .onAppear { appeared = true }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Primary group: the reading itself.
            Text(appState.displayValue)
                .font(.pixel(44))
                .foregroundStyle(Color(nsColor: appState.currentColor))
                .shadow(color: Color(nsColor: appState.currentColor).opacity(0.75), radius: 7)
            Text(appState.displayArrow)
                .font(.pixel(22))
                .foregroundStyle(Color(nsColor: appState.currentColor))
                .shadow(color: Color(nsColor: appState.currentColor).opacity(0.75), radius: 4)
                .accessibilityLabel(appState.currentEntry?.direction.accessibilityLabel ?? "")
            Text(appState.displayDelta)
                .font(.pixel(11))
                .foregroundStyle(Color.dsPhosphorDim)
            Text(appState.settings.unit.rawValue)
                .font(.caption)
                .foregroundStyle(Color.dsPhosphorDim.opacity(0.7))

            Spacer()

            // Meta group, right-aligned: badges, age, uploader battery.
            if appState.isStale {
                Label(L("stale"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color.dsStale)
            }
            if appState.isDemo {
                Text(L("DEMO MODE"))
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)
            }
            if let age = appState.dataAgeMinutes {
                Text(LF("%d min ago", age))
                    .font(.caption)
                    .foregroundStyle(appState.isStale ? Color.dsLow : Color.dsPhosphorDim)
            }
            if let battery = appState.deviceStatus?.uploaderBattery {
                Label("\(battery)%", systemImage: batteryIcon(battery))
                    .font(.caption)
                    .foregroundStyle(Color.dsPhosphorDim)
            }
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: Alert banner

    private func bannerColor(for kind: AlertKind) -> Color {
        switch kind {
        case .urgentLow: return Color.dsUrgentLow.opacity(0.5)
        case .urgentHigh: return Color.dsUrgentHigh.opacity(0.45)
        case .low: return Color.dsLow.opacity(0.35)
        case .high: return Color.dsHigh.opacity(0.3)
        default: return Color.dsStale.opacity(0.3)
        }
    }

    private func alertBanner(_ alert: AlertEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
            Text(alert.localizedMessage(unit: appState.settings.unit))
                .font(.callout.bold())
            Spacer()
            Button(L("Dismiss")) { appState.dismissAlert() }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bannerColor(for: alert.kind), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Picker(L("Window"), selection: $appState.chartWindowHours) {
                ForEach(windowOptions, id: \.self) { hours in
                    Text("\(hours)h").tag(hours)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Spacer()
            GhostIconButton(systemName: "arrow.clockwise", help: L("Refresh")) {
                appState.refresh()
            }
            GhostIconButton(systemName: "gearshape", help: L("Settings")) {
                appState.onOpenSettings?()
            }
            GhostIconButton(systemName: "power", help: L("Quit Macscout")) {
                NSApp.terminate(nil)
            }
        }
        .foregroundStyle(Color.dsPhosphorDim)
    }
}

private extension View {
    /// Organic staggered entrance: each block rises and fades in on its own
    /// beat while the window-frame spring is still travelling.
    func risesIn(_ appeared: Bool, beat: Int) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.3).delay(0.05 + Double(beat) * 0.05),
                       value: appeared)
    }
}

/// Quiet icon button that lights up a soft phosphor square on hover.
private struct GhostIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .foregroundStyle(hovering ? Color.dsPhosphorBright : Color.dsPhosphorDim)
                .background(Color.dsPhosphorBright.opacity(hovering ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
