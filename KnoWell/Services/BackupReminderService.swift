import Foundation
import UserNotifications

enum BackupReminderService {
    private static let enabledKey = "backup.reminder.enabled"
    private static let intervalDaysKey = "backup.reminder.intervalDays"
    private static let lastBackupKey = "backup.lastBackupDate"
    private static let notificationID = "knowell.backup.reminder"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var intervalDays: Int {
        get {
            let value = defaults.integer(forKey: intervalDaysKey)
            return value > 0 ? value : 7
        }
        set { defaults.set(max(1, newValue), forKey: intervalDaysKey) }
    }

    static var lastBackupDate: Date? {
        get { defaults.object(forKey: lastBackupKey) as? Date }
        set { defaults.set(newValue, forKey: lastBackupKey) }
    }

    @MainActor
    static func recordBackupCompleted(at date: Date = .now) {
        lastBackupDate = date
        reschedule()
    }

    @MainActor
    static func reschedule() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard isEnabled else { return }

        let dueDate: Date
        if let lastBackupDate {
            dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: lastBackupDate) ?? .now
        } else {
            dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: .now) ?? .now
        }

        guard dueDate > .now else {
            scheduleReminder(at: Calendar.current.date(byAdding: .hour, value: 12, to: .now) ?? .now)
            return
        }
        scheduleReminder(at: dueDate)
    }

    @MainActor
    private static func scheduleReminder(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = L10n.backupReminderTitle
        content.body = L10n.backupReminderBody
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
