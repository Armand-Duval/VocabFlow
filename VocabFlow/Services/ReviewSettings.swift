import Foundation

enum ReviewSettings {
    private static let dailyNewLimitKey = "review.dailyNewLimit"
    private static let dailyReviewLimitKey = "review.dailyReviewLimit"
    private static let dailyDateKey = "review.dailyDate"
    private static let dailyNewStudiedKey = "review.dailyNewStudied"
    private static let dailyReviewStudiedKey = "review.dailyReviewStudied"

    static let defaultDailyNewLimit = 20
    static let defaultDailyReviewLimit = 100

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    /// 每日新词上限；0 表示不限。
    static var dailyNewLimit: Int {
        get {
            let stored = defaults.object(forKey: dailyNewLimitKey) as? Int
            return stored ?? defaultDailyNewLimit
        }
        set {
            defaults.set(max(0, newValue), forKey: dailyNewLimitKey)
        }
    }

    /// 每日复习上限；0 表示不限。
    static var dailyReviewLimit: Int {
        get {
            let stored = defaults.object(forKey: dailyReviewLimitKey) as? Int
            return stored ?? defaultDailyReviewLimit
        }
        set {
            defaults.set(max(0, newValue), forKey: dailyReviewLimitKey)
        }
    }

    static var newStudiedToday: Int {
        resetDailyCountsIfNeeded()
        return defaults.integer(forKey: dailyNewStudiedKey)
    }

    static var reviewStudiedToday: Int {
        resetDailyCountsIfNeeded()
        return defaults.integer(forKey: dailyReviewStudiedKey)
    }

    static func recordStudy(wasNewCard: Bool, now: Date = .now) {
        resetDailyCountsIfNeeded(now: now)
        let key = wasNewCard ? dailyNewStudiedKey : dailyReviewStudiedKey
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func resetDailyCountsIfNeeded(now: Date = .now) {
        let today = dayIdentifier(for: now)
        if defaults.string(forKey: dailyDateKey) != today {
            defaults.set(today, forKey: dailyDateKey)
            defaults.set(0, forKey: dailyNewStudiedKey)
            defaults.set(0, forKey: dailyReviewStudiedKey)
        }
    }

    private static func dayIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
