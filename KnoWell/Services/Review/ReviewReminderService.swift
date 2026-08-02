import Foundation
import UserNotifications

enum ReviewReminderService {
    private static let notificationID = "knowell.review.daily"
    private static let enabledKey = "review.reminder.enabled"
    private static let hourKey = "review.reminder.hour"
    private static let minuteKey = "review.reminder.minute"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var reminderHour: Int {
        get {
            let stored = defaults.object(forKey: hourKey) as? Int
            return stored ?? 20
        }
        set { defaults.set(min(23, max(0, newValue)), forKey: hourKey) }
    }

    static var reminderMinute: Int {
        get {
            let stored = defaults.object(forKey: minuteKey) as? Int
            return stored ?? 0
        }
        set { defaults.set(min(59, max(0, newValue)), forKey: minuteKey) }
    }

    static var reminderDate: Date {
        Calendar.current.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    static func applyReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = components.hour ?? 20
        reminderMinute = components.minute ?? 0
    }

    static func reschedule(dueCount: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard isEnabled, dueCount > 0 else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "KnoWell"
            content.body = L10n.reviewReminderBody(dueCount)
            content.sound = .default

            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: notificationID,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
}
