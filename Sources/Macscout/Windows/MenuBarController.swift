import AppKit
import Combine
import MacscoutCore

/// NSStatusItem showing the current BG ("118 ↗") colored by range, plus the
/// app menu (Open Panel / Refresh / Settings… / Check for Updates… / Quit).
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private let onOpenPanel: () -> Void
    private let onSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private var cancellables = Set<AnyCancellable>()
    /// Refresh the "x min ago" tooltip periodically.
    private var tooltipTimer: Timer?

    init(appState: AppState,
         onOpenPanel: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void = {}) {
        self.appState = appState
        self.onOpenPanel = onOpenPanel
        self.onSettings = onSettings
        self.onCheckForUpdates = onCheckForUpdates
        super.init()

        if appState.settings.showMenuBarIcon {
            createStatusItem()
        }

        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)

        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTooltip() }
        }
    }

    deinit {
        tooltipTimer?.invalidate()
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.menu = makeMenu()
        statusItem = item
        updateTitle()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Open Panel"), action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: L("Refresh"), action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Settings…"), action: #selector(settings), keyEquivalent: ",")
        menu.addItem(withTitle: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Macscout"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    /// Applies the show/hide menu bar icon setting.
    func updateVisibility() {
        if appState.settings.showMenuBarIcon, statusItem == nil {
            createStatusItem()
        } else if !appState.settings.showMenuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Rebuilds the menu with re-resolved localized titles.
    func reloadContent() {
        statusItem?.menu = makeMenu()
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        // Plain title: system label color, like every other menu bar item.
        // Range colors live in the band and panel.
        button.title = appState.menuBarText
        button.setAccessibilityLabel(LF("Blood glucose %@, %@", appState.displayValue, L(appState.currentEntry?.direction.accessibilityLabel ?? "")))
        updateTooltip()
    }

    private func updateTooltip() {
        statusItem?.button?.toolTip = appState.tooltipText
    }

    @objc private func openPanel() { onOpenPanel() }
    @objc private func refresh() { appState.refresh() }
    @objc private func settings() { onSettings() }
    @objc private func checkForUpdates() { onCheckForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
