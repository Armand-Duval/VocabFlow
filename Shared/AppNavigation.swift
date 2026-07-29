import Foundation

extension Notification.Name {
    /// `userInfo["tab"]` as `Int` — 0 review, 1 library, 2 create
    static let requestAppTab = Notification.Name("com.knowell.requestAppTab")
    static let requestSettings = Notification.Name("com.knowell.requestSettings")
}

enum AppTab: Int {
    case review = 0
    case library = 1
    case create = 2

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
