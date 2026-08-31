import Foundation

extension Notification.Name {
    /// `userInfo["tab"]` as `Int` — 0 review, 1 library, 2 create, 3 settings
    static let requestAppTab = Notification.Name("com.knowell.requestAppTab")
    static let requestSettings = Notification.Name("com.knowell.requestSettings")
    /// User tapped the share-inbox local notification.
    static let shareInboxNotificationTapped = Notification.Name("com.knowell.shareInboxNotificationTapped")
}

enum AppTab: Int {
    case review = 0
    case library = 1
    case create = 2
    case settings = 3

    static func request(_ tab: AppTab) {
        NotificationCenter.default.post(
            name: .requestAppTab,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    static func requestSettings() {
        NotificationCenter.default.post(name: .requestSettings, object: nil)
    }
}
