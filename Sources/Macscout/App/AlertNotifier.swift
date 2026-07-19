import Foundation
import UserNotifications
import MacscoutCore

/// Posts alert banners via UNUserNotificationCenter.
///
/// Defensive by design: ad-hoc signed dev builds may fail to register with the
/// notification center (missing provisioning/entitlements). Any failure is
/// logged and otherwise ignored — sounds and the in-panel alert still work.
@MainActor
final class AlertNotifier: NSObject {
    private let center = UNUserNotificationCenter.current()
    private var available = false

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Macscout: notification authorization failed: \(error.localizedDescription)")
            }
            Task { @MainActor in
                self.available = granted
            }
        }
    }

    func post(_ event: AlertEvent, unit: GlucoseUnit) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Macscout — \(event.kind.localizedName)"
        content.body = event.localizedMessage(unit: unit)
        if event.kind.isUrgent {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(
            identifier: "macscout-\(event.kind.rawValue)-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                NSLog("Macscout: failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

extension AlertNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
