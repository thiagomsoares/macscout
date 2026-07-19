import AppKit
import SwiftUI
import MacscoutCore

/// Presents the first-launch onboarding: a fullscreen click-through backdrop
/// plus a centered card window that steps through the five acts.
@MainActor
final class OnboardingWindowController {
    private let appState: AppState
    private let onDismiss: () -> Void
    private let model: OnboardingModel
    private var backdrop: NSWindow?
    private var card: OnboardingCardWindow?

    private let cardSize = NSSize(width: 620, height: 560)

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.onDismiss = onDismiss
        self.model = OnboardingModel(settings: appState.settings, appState: appState)
        model.onFinish = { [weak self] in self?.finish() }
    }

    /// Shows the backdrop and card, and brings the app to the front.
    func present() {
        // Same screen as the notch pill: the primary display (frame origin 0,0),
        // so the glow and the "the pill up there" story line up visually.
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]

        let backdropWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        // ARC owns these windows (stored properties) — close() must not
        // release them too, or the pool drain double-releases and crashes.
        backdropWindow.isReleasedWhenClosed = false
        backdropWindow.backgroundColor = .clear
        backdropWindow.isOpaque = false
        backdropWindow.contentView = NSHostingView(rootView: RaysBackdropView())
        backdropWindow.ignoresMouseEvents = true
        backdropWindow.level = .normal
        backdropWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        backdrop = backdropWindow

        let cardOrigin = NSPoint(
            x: screen.frame.midX - cardSize.width / 2,
            y: screen.frame.midY - cardSize.height / 2)
        let cardWindow = OnboardingCardWindow(
            contentRect: NSRect(origin: cardOrigin, size: cardSize),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        cardWindow.isReleasedWhenClosed = false
        cardWindow.backgroundColor = .clear
        cardWindow.isOpaque = false
        cardWindow.hasShadow = true
        cardWindow.level = .floating
        cardWindow.contentView = NSHostingView(rootView: OnboardingView(model: model))
        card = cardWindow

        backdropWindow.orderFrontRegardless()
        cardWindow.orderFrontRegardless()

        // Foreground the app while the card is up; back to agent on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        cardWindow.makeKey()

        appState.onboardingGlow = true
    }

    /// Ceremony complete or skipped: mark done and tear down.
    private func finish() {
        appState.settings.hasCompletedOnboarding = true
        close()
    }

    private func close() {
        appState.onboardingGlow = false
        appState.onboardingGlowPulse = false
        card?.close()
        backdrop?.close()
        card = nil
        backdrop = nil
        NSApp.setActivationPolicy(.accessory)
        onDismiss()
    }
}

/// Borderless card window that can take key status (text fields) and ignores
/// ESC (no accidental dismissal).
private final class OnboardingCardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return } // ESC: do nothing
        super.keyDown(with: event)
    }
}
