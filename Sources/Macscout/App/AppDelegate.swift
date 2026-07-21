import AppKit
import Combine
import SwiftUI
import MacscoutCore

/// Application delegate: wires up app state, menu bar item, and notch window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState!
    private(set) var updates: UpdateController!
    private var menuBar: MenuBarController?
    private var notchWindow: NotchWindowController?
    private var settingsWindow: NSWindow?
    private var onboarding: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        PixelFont.register()
        let settings = SettingsStore()
        L10n.apply(settings.appLanguage) // before any UI exists
        let state = AppState(settings: settings)
        appState = state
        updates = UpdateController()

        // Language switch: re-resolve the localization bundle and rebuild
        // every visible surface (delivered after didSet — see AppState note).
        settings.$appLanguage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLanguageChange() }
            .store(in: &cancellables)

        menuBar = MenuBarController(appState: state,
                                    onOpenPanel: { [weak self] in self?.togglePanel() },
                                    onSettings: { [weak self] in self?.showSettings() },
                                    onCheckForUpdates: { [weak self] in self?.updates.checkAndPresentAlert() })
        notchWindow = NotchWindowController(appState: state)

        state.onUrgentAlert = { [weak self] in
            self?.notchWindow?.expand()
        }
        state.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        state.onVisibilityChanged = { [weak self] in
            self?.menuBar?.updateVisibility()
            self?.notchWindow?.updateVisibility()
        }
        state.onReplayOnboarding = { [weak self] in
            self?.showOnboarding()
        }
        state.start()

        if !settings.hasCompletedOnboarding {
            // Let the notch pill appear first so the glow lands on it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showOnboarding()
            }
        }

        // Quiet launch check — only surfaces in About if something newer exists.
        // Delay so we don't compete with first-run onboarding / Nightscout poll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.updates.checkInBackground()
        }
    }

    /// Re-resolves the language bundle and rebuilds the localized surfaces.
    private func applyLanguageChange() {
        L10n.apply(appState.settings.appLanguage)
        notchWindow?.reloadContent()
        menuBar?.reloadContent()
        if let window = settingsWindow {
            window.title = L("Macscout Settings")
            window.contentView = NSHostingView(rootView: SettingsView(appState: appState, updates: updates))
        }
    }

    /// Presents the onboarding flow (first launch or "Replay Onboarding…").
    func showOnboarding() {
        guard onboarding == nil else { return }
        let controller = OnboardingWindowController(appState: appState) { [weak self] in
            self?.onboarding = nil
        }
        onboarding = controller
        controller.present()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }

    private func togglePanel() {
        notchWindow?.toggle()
    }

    /// Opens (or focuses) the settings window.
    func showSettings() {
        if let window = settingsWindow {
            // isReleasedWhenClosed == false, so the same instance can be re-shown —
            // reusing avoids accumulating abandoned windows on every open.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = SettingsView.makeWindow(appState: appState, updates: updates)
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
