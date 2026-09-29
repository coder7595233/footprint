import AppKit
import Foundation
import UserNotifications

final class AppNotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private weak var store: GrantDataStore?

    @MainActor
    func configure(store: GrantDataStore, center: UNUserNotificationCenter) {
        self.store = store
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let kind = userInfo["kind"] as? String
        let dayString = userInfo["dayString"] as? String
        let applicationID = userInfo["applicationID"] as? String
        let primaryLink = userInfo["primaryLink"] as? String
        let store = self.store
        completionHandler()
        DispatchQueue.main.async {
            guard let store else { return }
            if kind == "calendarTaskReminder" {
                if let dayString,
                   let date = DateParsers.isoDay.date(from: dayString) {
                    store.revealCalendarWorkspace(on: date)
                } else {
                    store.revealCalendarWorkspace()
                }
            } else {
                if let applicationID {
                    store.route = AppRoute(recordID: applicationID, destination: .applications)
                }
                if let rawLink = primaryLink,
                   let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                   let url = normalizedWebLinkURL(trimmed) {
                    NSWorkspace.shared.open(url)
                }
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
