import SwiftUI
import MacscoutCore

/// Root content of the notch panel: collapsed pill or expanded dashboard.
struct NotchPanelRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var notchState: NotchState

    var body: some View {
        Group {
            if notchState.expanded {
                ExpandedPanelView(appState: appState)
            } else {
                NotchView(appState: appState, notchState: notchState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { inside in
            notchState.onHover?(inside)
        }
        // IMPORTANT: no implicit animation on the expanded/collapsed swap.
        // Animating this conditional Group can wedge the content on the stale
        // view during rapid toggles (expanded frame + collapsed content bug).
        // The window-frame spring provides all the motion; content swaps instantly.
    }
}

/// Collapsed band: an ear of content on each side of the notch — glucose value
/// + trend on the left, sparkline + delta on the right. Gray "!" when stale.
struct NotchView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var notchState: NotchState
    @State private var landingScale: CGFloat = 1.0
    @State private var popScale: CGFloat = 1.0

    private var textColor: Color { Color(nsColor: appState.currentColor) }
    private var layout: NotchState.CollapsedLayout { notchState.collapsedLayout }

    /// Concave ears only make sense against the menu bar; the floating pill
    /// (no hardware notch) keeps a plain top edge.
    private var bandShape: NotchBandShape {
        NotchBandShape(topCornerRadius: layout.notchWidth > 0 ? 6 : 0,
                       bottomCornerRadius: 13)
    }

    private var isUrgent: Bool {
        guard let kind = appState.activeAlert?.kind else { return false }
        return kind == .urgentLow || kind == .urgentHigh
    }

    /// The band's status icon slot: green drop in range, yellow caution out
    /// of range, red caution when urgent, special sprites on magic values
    /// (100 = unicorn, 101 = dalmatian…). Urgent always wins over a sprite.
    private enum BandIcon: Equatable {
        case drop(Color)
        case sprite(PixelSprite)
    }

    private var bandIcon: BandIcon {
        guard let entry = appState.currentEntry else { return .drop(Color.dsInRange) }
        if appState.isStale { return .drop(Color.dsStale) }
        let alerts = appState.settings.alertSettings
        let urgent = entry.sgv <= alerts.urgentLowThreshold
            || entry.sgv >= alerts.urgentHighThreshold
        if urgent { return .sprite(StatusIcons.cautionUrgent) }
        if let special = SpecialGlucoseIcons.sprite(for: entry.sgv) {
            return .sprite(special)
        }
        if entry.sgv < alerts.lowThreshold || entry.sgv > alerts.highThreshold {
            return .sprite(StatusIcons.cautionOutOfRange)
        }
        return .drop(Color.dsInRange)
    }

    var body: some View {
        Button {
            // Click pins the panel open — suppress hover auto-collapse.
            notchState.expandedByHover = false
            notchState.expanded.toggle()
        } label: {
            HStack(spacing: 0) {
                // Left ear — animated brand drop + value + trend, anchored to
                // the band's left edge (text ≈ 1/3 of the band height, icon
                // slightly taller).
                HStack(spacing: 5) {
                    switch bandIcon {
                    case .drop(let color):
                        PulsingPixelIconView(color: color)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    case .sprite(let sprite):
                        PixelIconView(sprite: sprite, pixelSize: 1.4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    Text(appState.displayValue)
                        .font(.pixel(14))
                        .foregroundStyle(textColor)
                        .shadow(color: textColor.opacity(0.7), radius: 3)
                        .scaleEffect(popScale)
                        .phaseAnimator([false, true], trigger: isUrgent) { content, phase in
                            content.shadow(
                                color: isUrgent ? Color.dsUrgentLow.opacity(phase ? 0.9 : 0.15) : .clear,
                                radius: phase ? 8 : 2)
                        } animation: { _ in .easeInOut(duration: 0.8) }
                        .onChange(of: appState.currentEntry?.id) { popValue() }
                    if appState.isStale {
                        Text("!")
                            .font(.pixel(10))
                            .foregroundStyle(Color.dsStale)
                    } else {
                        Text(appState.displayArrow)
                            .font(.pixel(10))
                            .foregroundStyle(textColor)
                            .accessibilityLabel(L(appState.currentEntry?.direction.accessibilityLabel ?? ""))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: max(layout.earWidth - 14, 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: bandIcon)

                // The camera zone stays empty (the hardware cutout blends it).
                Color.clear.frame(width: layout.notchWidth)

                // Right ear — delta/DEMO + 12 h pixel trail, anchored to the
                // band's right edge.
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if appState.isDemo {
                        Text(L("DEMO"))
                            .font(.system(size: 7, weight: .heavy))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.orange)
                    } else if !appState.displayDelta.isEmpty {
                        Text(appState.displayDelta)
                            .font(.pixel(10))
                            .foregroundStyle(Color(nsColor: DSColors.textSecondary))
                    }
                    SparklineView(entries: appState.entries,
                                  alertSettings: appState.settings.alertSettings)
                        .frame(width: 46, height: 18)
                }
                .frame(width: max(layout.earWidth - 14, 0))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.black, in: bandShape)
        // Subtle hairline following the notch contour (visible on light
        // backgrounds, melts away on dark ones).
        .overlay(bandShape.stroke(.white.opacity(0.12), lineWidth: 1))
        .clipShape(bandShape)
        .overlay {
            if appState.onboardingGlow {
                PillGlowOverlay(shape: bandShape)
            }
        }
        .shadow(color: appState.onboardingGlow ? .blue.opacity(0.75) : .clear,
                radius: appState.onboardingGlowPulse ? 24 : 10)
        .scaleEffect(landingScale)
        .animation(.easeInOut(duration: 0.4), value: appState.onboardingGlowPulse)
        // Pill "landing bounce" (onboarding ceremony): 1 → 1.12 → 1.
        .onChange(of: appState.pillLanding) { _, landing in
            guard landing else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                landingScale = 1.12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    landingScale = 1.0
                }
                appState.pillLanding = false
            }
        }
        .accessibilityLabel(LF("Blood glucose %@, %@", appState.displayValue, L(appState.currentEntry?.direction.accessibilityLabel ?? "")))
    }

    /// Quick spring "pop" on the value whenever a new reading arrives.
    private func popValue() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { popScale = 1.18 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { popScale = 1.0 }
        }
    }
}

/// The notch band contour: concave top
/// "ears" (`topCornerRadius`) where the band melts out of the menu bar,
/// and convex bottom corners (`bottomCornerRadius`). The body is inset by
/// the top radius on each side; the top edge spans the full frame width.
struct NotchBandShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        let top = topCornerRadius
        let bottom = bottomCornerRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave left ear.
        p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                       control: CGPoint(x: rect.minX + top, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Convex bottom-left corner.
        p.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                       control: CGPoint(x: rect.minX + top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Convex bottom-right corner.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                       control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Concave right ear.
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - top, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Rotating angular-gradient stroke used to draw attention to the pill
/// during onboarding.
private struct PillGlowOverlay: View {
    let shape: NotchBandShape
    @State private var angle = 0.0

    var body: some View {
        shape
            .stroke(
                AngularGradient(colors: [.blue, .mint, .purple, .blue],
                                center: .center, angle: .degrees(angle)),
                lineWidth: 2)
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
