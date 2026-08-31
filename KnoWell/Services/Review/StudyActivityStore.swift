import Foundation

/// Local rolling study activity — unique words / sentences per day.
/// Soft encouragement only; no ranking or social comparison.
enum StudyActivityStore {
    private static let storageKey = "com.knowell.study.activity.v1"
    private static let lookbackDays = 7
    private static let retentionDays = 40
    private static let maxKeysPerDay = 400

    private static var calendar: Calendar { .current }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    struct Summary: Equatable {
        /// Calendar span from earliest active day in the window through today (1 = today only).
        let spanDays: Int
        let uniqueWords: Int
        let uniqueSentences: Int
    }

    /// Call when the user rates a card.
    static func record(word: String, sentence: String, now: Date = .now) {
        let wordKey = FlashCardDeduper.normalizedWord(word)
        let sentenceKey = FlashCardDeduper.normalizedSentence(sentence)
        guard !wordKey.isEmpty || !sentenceKey.isEmpty else { return }

        var buckets = loadBuckets()
        let day = dayFormatter.string(from: now)
        var bucket = buckets[day] ?? DayBucket()

        if !wordKey.isEmpty,
           bucket.words.count < maxKeysPerDay || bucket.words.contains(wordKey) {
            bucket.words.insert(wordKey)
        }
        let sentenceID = stableSentenceKey(sentenceKey)
        if !sentenceKey.isEmpty,
           bucket.sentences.count < maxKeysPerDay || bucket.sentences.contains(sentenceID) {
            bucket.sentences.insert(sentenceID)
        }

        buckets[day] = bucket
        prune(&buckets, now: now)
        saveBuckets(buckets)
    }

    static func recordedDayCount() -> Int {
        loadBuckets().values.filter { !$0.words.isEmpty || !$0.sentences.isEmpty }.count
    }

    static func recentSummary(now: Date = .now) -> Summary? {
        let buckets = loadBuckets()
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: todayStart) else {
            return nil
        }

        var words = Set<String>()
        var sentences = Set<String>()
        var activeDayStarts: [Date] = []

        for offset in 0..<lookbackDays {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: windowStart) else { continue }
            let key = dayFormatter.string(from: dayDate)
            guard let bucket = buckets[key], !bucket.words.isEmpty || !bucket.sentences.isEmpty else { continue }
            words.formUnion(bucket.words)
            sentences.formUnion(bucket.sentences)
            activeDayStarts.append(calendar.startOfDay(for: dayDate))
        }

        guard !words.isEmpty || !sentences.isEmpty,
              let earliest = activeDayStarts.min() else {
            return nil
        }

        let span = max(1, (calendar.dateComponents([.day], from: earliest, to: todayStart).day ?? 0) + 1)
        return Summary(
            spanDays: span,
            uniqueWords: words.count,
            uniqueSentences: sentences.count
        )
    }

    // MARK: - Persistence

    private struct DayBucket: Codable {
        var words: Set<String> = []
        var sentences: Set<String> = []
    }

    private static func loadBuckets() -> [String: DayBucket] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: DayBucket].self, from: data)) ?? [:]
    }

    private static func saveBuckets(_ buckets: [String: DayBucket]) {
        guard let data = try? JSONEncoder().encode(buckets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func prune(_ buckets: inout [String: DayBucket], now: Date) {
        let todayStart = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: todayStart) else { return }
        buckets = buckets.filter { key, _ in
            guard let date = dayFormatter.date(from: key) else { return false }
            return date >= cutoff
        }
    }

    private static func stableSentenceKey(_ normalized: String) -> String {
        // Keep storage small: length + prefix is enough for personal uniqueness.
        let prefix = String(normalized.prefix(96))
        return "\(normalized.count)|\(prefix)"
    }
}
