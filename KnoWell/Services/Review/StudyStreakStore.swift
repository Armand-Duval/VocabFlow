import Foundation

/// Lightweight local study streak (days with at least one review rating).
enum StudyStreakStore {
    private static let streakKey = "com.knowell.study.streak"
    private static let lastDayKey = "com.knowell.study.lastDay"

    private static var calendar: Calendar { Calendar.current }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static var currentStreak: Int {
        recordIfNeeded(now: .now)
        return UserDefaults.standard.integer(forKey: streakKey)
    }

    /// Call when the user rates a card.
    static func recordStudy(now: Date = .now) {
        let today = dayFormatter.string(from: now)
        let last = UserDefaults.standard.string(forKey: lastDayKey)

        if last == today {
            return
        }

        if let last,
           let lastDate = dayFormatter.date(from: last),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(lastDate, inSameDayAs: yesterday) {
            UserDefaults.standard.set(max(1, UserDefaults.standard.integer(forKey: streakKey)) + 1, forKey: streakKey)
        } else {
            UserDefaults.standard.set(1, forKey: streakKey)
        }
        UserDefaults.standard.set(today, forKey: lastDayKey)
    }

    private static func recordIfNeeded(now: Date) {
        let today = dayFormatter.string(from: now)
        let last = UserDefaults.standard.string(forKey: lastDayKey)
        guard let last, last != today else { return }
        guard let lastDate = dayFormatter.date(from: last) else { return }
        let startToday = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday),
              !calendar.isDate(lastDate, inSameDayAs: yesterday) else {
            return
        }
        // Broken streak — keep last value until next study day resets on recordStudy.
        // Soft-expire display to 0 if gap > 1 day.
        if lastDate < yesterday {
            UserDefaults.standard.set(0, forKey: streakKey)
        }
    }
}
