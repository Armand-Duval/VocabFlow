import Foundation

extension Notification.Name {
    static let reviewQueueDidChange = Notification.Name("reviewQueueDidChange")
}

enum ReviewStatusStore {
    private static let dueCountKey = "review.dueCount"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var dueCount: Int {
        defaults.integer(forKey: dueCountKey)
    }

    static func updateDueCount(_ count: Int) {
        defaults.set(max(0, count), forKey: dueCountKey)
    }
}
