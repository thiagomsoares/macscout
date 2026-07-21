import AppKit
import Combine
import SwiftUI
import MacscoutCore

/// Shared expand/collapse state for the notch panel.
@MainActor
final class NotchState: ObservableObject {
    /// Geometry of the collapsed band, published for the SwiftUI layout.
    struct CollapsedLayout: Equatable {
        var notchWidth: CGFloat
        var earWidth: CGFloat
    }

    @Published var expanded = false
    @Published var collapsedLayout = CollapsedLayout(notchWidth: 0, earWidth: 100)
    /// True when the current expansion was caused by hovering (not a click) —
    /// only hover-caused expansions auto-collapse when the pointer leaves.
    var expandedByHover = false
    /// Set by NotchWindowController; called by views on pointer enter/exit.
    var onHover: ((Bool) -> Void)?
}

/// Borderless panel that mimics the notch: collapsed it sits flush in the
/// notch area as a black pill; expanded it becomes a rounded dashboard.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let state = NotchState()
    private let appState: AppState
    private var hosting: NotchContentView!
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let springAnimator = SpringFrameAnimator()
    private var screenObserver: NSObjectProtocol?

    private let expandedSize = NSSize(width: 700, height: 380)
    /// Expanded panel uses a slightly looser bottom radius than the band.
    private let expandedBottomRadius: CGFloat = 16
    private let collapsedBottomRadius: CGFloat = 13
    private let topCornerRadius: CGFloat = 6

    init(appState: AppState) {
        self.appState = appState
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 200, height: 36)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // fullScreenAuxiliary keeps the pill visible above fullscreen apps
        // (Keynote, games, immersive video) instead of disappearing with the
        // menu bar. ignoresCycle keeps ⌘` from landing on a chrome-less panel.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
        ]
        panel.isMovable = false
        panel.onEscape = { [weak self] in self?.collapse() }
        state.onHover = { [weak self] inside in
            inside ? self?.hoverEntered() : self?.hoverExited()
        }

        let root = NotchPanelRootView(appState: appState, notchState: state)
        hosting = NotchContentView(rootView: root)
        hosting.isExpanded = { [weak self] in self?.state.expanded ?? false }
        hosting.collapsedLayout = { [weak self] in
            self?.state.collapsedLayout ?? .init(notchWidth: 0, earWidth: 100)
        }
        hosting.topCornerRadius = topCornerRadius
        hosting.collapsedBottomRadius = collapsedBottomRadius
        hosting.expandedBottomRadius = expandedBottomRadius
        panel.contentView = hosting

        // NOTE: @Published emits in willSet — reading state.expanded inside the
        // sink would return the OLD value and animate the frame to the opposite
        // state (expanded content in collapsed frame and vice-versa). Always use
        // the value delivered by the publisher.
        state.$expanded.dropFirst().sink { [weak self] newValue in
            self?.animateFrameChange(expanded: newValue)
        }.store(in: &cancellables)

        installMonitors()
        updateVisibility()
        // Place the collapsed pill at the notch right away — collapse() early-returns
        // when not expanded and would leave the panel at its initial .zero origin.
        animateFrameChange(snap: true)

        // Re-anchor when displays are connected/disconnected or rearranged.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.animateFrameChange(snap: true) }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    // MARK: - Geometry

    /// Primary display (frame origin 0,0) — the panel is pinned to it.
    private var targetScreen: NSScreen {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
    }

    /// True when the screen has a hardware notch (top safe area inset).
    private func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Width of the camera housing area, derived from the auxiliary areas.
    private func notchWidth(_ screen: NSScreen) -> CGFloat {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let computed = screen.frame.width - left - right
        return computed > 0 ? computed : 190
    }

    /// Width of each content "ear" flanking the notch in the collapsed band.
    /// 90pt/side keeps the band compact; the camera zone in the middle is
    /// never covered.
    private let earWidth: CGFloat = 90

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        if hasNotch(screen) {
            // Wide band: the notch footprint plus content ears extending into the
            // menu bar on both sides (the hardware cutout blends the middle).
            let notch = notchWidth(screen)
            let width = notch + earWidth * 2
            let height = max(screen.safeAreaInsets.top, 32)
            state.collapsedLayout = .init(notchWidth: notch, earWidth: earWidth)
            return NSRect(x: screenFrame.midX - width / 2,
                          y: screenFrame.maxY - height,
                          width: width, height: height)
        }
        // Floating pill just under the menu bar (no cutout — ears touch).
        // In a fullscreen space the menu bar is auto-hidden; park the pill on
        // the top edge so it stays glanceable without a status strip.
        state.collapsedLayout = .init(notchWidth: 0, earWidth: earWidth)
        let menuH = menuBarHeight(screen)
        let y: CGFloat
        if isFullscreenSpace(screen) {
            y = screenFrame.maxY - 36
        } else {
            y = screenFrame.maxY - menuH - 6 - 36
        }
        return NSRect(x: screenFrame.midX - earWidth,
                      y: y,
                      width: earWidth * 2, height: 36)
    }

    private func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        // Visible frame starts below the menu bar on notch-less screens.
        screen.frame.height - screen.visibleFrame.height - screen.safeAreaInsets.top
    }

    /// Menu bar is auto-hidden (typical of a fullscreen Space).
    private func isFullscreenSpace(_ screen: NSScreen) -> Bool {
        screen.visibleFrame.maxY >= screen.frame.maxY - 1
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        return NSRect(x: screenFrame.midX - expandedSize.width / 2,
                      y: screenFrame.maxY - expandedSize.height,
                      width: expandedSize.width,
                      height: expandedSize.height)
    }

    // MARK: - Expand / collapse

    func toggle() {
        // Explicit click: the expansion is user-pinned, never hover-collapsed.
        state.expandedByHover = false
        state.expanded ? collapse() : expand()
    }

    func expand() {
        guard !state.expanded else { return }
        state.expanded = true
    }

    func collapse(animated: Bool = true) {
        guard state.expanded else { return }
        state.expanded = false
        state.expandedByHover = false
        if !animated {
            animateFrameChange(snap: true)
        }
    }

    // MARK: - Hover expansion

    private var hoverWork: DispatchWorkItem?

    private func hoverEntered() {
        hoverWork?.cancel()
        guard appState.settings.expandOnHover else { return }
        guard !state.expanded else { return } // already open; leave as-is
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.state.expandedByHover = true
            self.state.expanded = true
        }
        hoverWork = work
        // Small rest delay so passing the pointer over the notch doesn't flash the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func hoverExited() {
        hoverWork?.cancel()
        guard state.expanded, state.expandedByHover else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.expanded, self.state.expandedByHover else { return }
            self.state.expanded = false
            self.state.expandedByHover = false
        }
        hoverWork = work
        // Grace period lets the pointer travel from the pill into the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Animates the panel to the frame for `expanded`. Callers outside the
    /// Combine pipeline may omit it to read the (settled) current state.
    private func animateFrameChange(expanded: Bool? = nil, snap: Bool = false) {
        let isExpanded = expanded ?? state.expanded
        let screen = targetScreen
        let frame = isExpanded ? expandedFrame(on: screen) : collapsedFrame(on: screen)
        panel.styleMask.insert(.nonactivatingPanel)
        if snap {
            springAnimator.stop()
            panel.setFrame(frame, display: true)
        } else if let contentView = panel.contentView {
            // Spring-driven frame change (expand is lively, collapse is drier);
            // the animator always snaps the exact final frame on completion.
            springAnimator.animate(view: contentView, from: panel.frame, to: frame,
                                   spring: isExpanded ? .expand : .collapse) { [panel] newFrame in
                panel.setFrame(newFrame, display: true)
            } onComplete: { [weak self] in
                // Self-heal: if state changed while the spring ran, land on the
                // frame that matches the CURRENT state instead of the stale target.
                guard let self else { return }
                let expected = self.state.expanded
                    ? self.expandedFrame(on: self.targetScreen)
                    : self.collapsedFrame(on: self.targetScreen)
                if !self.panel.frame.equalTo(expected) {
                    self.panel.setFrame(expected, display: true)
                }
            }
        }
        if isExpanded {
            panel.makeKey()
        }
    }

    private func installMonitors() {
        // Click anywhere outside the panel (any app) collapses it.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.state.expanded else { return }
            self.collapse()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.state.expanded else { return event }
            if event.window !== self.panel {
                self.collapse()
            }
            return event
        }
    }

    func updateVisibility() {
        panel.orderFrontRegardless()
    }

    /// Rebuilds the SwiftUI tree (e.g. after a language change) so all
    /// localized strings re-resolve.
    func reloadContent() {
        hosting.rootView = NotchPanelRootView(appState: appState, notchState: state)
    }
}

// MARK: - Content view (shape-aware hit testing)

/// Hosts the SwiftUI tree and owns pointer hit-testing for the notch chrome.
///
/// The window frame is a rectangle, but the visible chrome is `NotchBandShape`.
/// Returning `nil` from `hitTest` for empty corners and the camera housing lets
/// menu-bar items (and the desktop under a floating pill) keep their clicks.
private final class NotchContentView: NSHostingView<NotchPanelRootView> {
    var isExpanded: () -> Bool = { false }
    var collapsedLayout: () -> NotchState.CollapsedLayout = {
        .init(notchWidth: 0, earWidth: 100)
    }
    var topCornerRadius: CGFloat = 6
    var collapsedBottomRadius: CGFloat = 13
    var expandedBottomRadius: CGFloat = 16

    /// First click on the pill counts even when Macscout is not the active app —
    /// critical for a status-level chrome that must never require a focus steal.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }

        let expanded = isExpanded()
        let bottom = expanded ? expandedBottomRadius : collapsedBottomRadius
        // Collapsed floating pill has no concave ears (top radius 0).
        let top: CGFloat = {
            if expanded { return topCornerRadius }
            return collapsedLayout().notchWidth > 0 ? topCornerRadius : 0
        }()

        if !expanded {
            let layout = collapsedLayout()
            if let camera = NotchBandGeometry.cameraZone(in: bounds, notchWidth: layout.notchWidth),
               camera.contains(point) {
                return nil
            }
        }

        if !NotchBandGeometry.contains(point, in: bounds,
                                       topCornerRadius: top,
                                       bottomCornerRadius: bottom,
                                       yIncreasesUp: true) {
            return nil
        }

        return super.hitTest(point)
    }
}

/// NSPanel subclass that resigns key status on escape.
/// First-click handling lives on `NotchContentView.acceptsFirstMouse`.
private final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
