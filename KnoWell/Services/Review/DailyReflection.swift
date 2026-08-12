import Foundation

/// A gentle daily sentence for the review home — original text first, then translation.
struct DailyReflection: Equatable {
    /// Original wording the reader should see first (any language / classical Chinese).
    let sentence: String
    /// Chinese translation / vernacular when `sentence` is not already modern Chinese.
    let translation: String?
    let source: String?
    /// Optional short seasonal / cultural note (e.g. “立秋将近”), never required.
    let occasion: String?
    /// True when produced by AI for the calendar day (vs curated fallback).
    let isAI: Bool

    var displaySentence: String {
        LiteraryTextFormatting.display(sentence)
    }

    var displayTranslation: String? {
        guard let translation else { return nil }
        let formatted = LiteraryTextFormatting.display(translation)
        return formatted.isEmpty ? nil : formatted
    }

    var quoteSourceAttribution: String? {
        LiteraryTextFormatting.sourceParts(source: source, sentence: sentence).quote
    }

    var translationSourceAttribution: String? {
        LiteraryTextFormatting.sourceParts(source: source, sentence: sentence).translation
    }
}

/// Normalizes poetry line breaks for storage and display (AI sometimes emits " / " or "，/").
enum LiteraryTextFormatting {
    static func display(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Punctuation + optional spaces + slash + optional spaces → newline after punctuation.
        result = replaceRegex(
            in: result,
            pattern: #"([，,；;：:])\s*/\s*"#,
            template: "$1\n"
        )

        // Remaining slash breaks with surrounding whitespace.
        result = replaceRegex(
            in: result,
            pattern: #"\s+/+\s+"#,
            template: "\n"
        )

        return result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reject AI output that uses symbols the reader should never see in a literary quote.
    static func containsInvalidMarkers(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("/") {
            return true
        }
        if trimmed.contains("```") || trimmed.contains("**") || trimmed.contains("__") || trimmed.contains("<") {
            return true
        }
        if trimmed.contains("\\n") || trimmed.contains("|") {
            return true
        }
        return false
    }

    /// Split source for quote vs translation attribution blocks.
    static func sourceParts(source: String?, sentence: String) -> (quote: String?, translation: String?) {
        guard let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        if raw.contains(" | ") {
            let parts = raw
                .components(separatedBy: " | ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                let firstIsLatin = latinLetterCount(parts[0]) > hanCount(parts[0])
                let secondIsLatin = latinLetterCount(parts[1]) > hanCount(parts[1])
                if firstIsLatin, !secondIsLatin {
                    return (parts[0], parts[1])
                }
                if secondIsLatin, !firstIsLatin {
                    return (parts[1], parts[0])
                }
                return (parts[0], parts[1])
            }
        }

        let sentenceIsEnglish = latinLetterCount(sentence) >= 4 && latinLetterCount(sentence) > hanCount(sentence)
        let sourceIsLatin = latinLetterCount(raw) > hanCount(raw)
        if sentenceIsEnglish {
            if sourceIsLatin {
                return (raw, nil)
            }
            return (nil, raw)
        }
        return (nil, raw)
    }

    static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count
    }

    static func hanCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
    }

    private static func replaceRegex(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// One calendar day's reflection kept for later browsing (local archive).
struct ArchivedDailyReflection: Identifiable, Equatable, Codable {
    let id: String
    let dayKey: String
    let sentence: String
    let translation: String?
    let source: String?
    let occasion: String?
    let isAI: Bool
    /// Hand-picked seed for a past day; protected from curated overwrite.
    var isManualSeed: Bool
    /// Newest first within the same day (refresh keeps prior lines).
    var savedAt: Double

    enum CodingKeys: String, CodingKey {
        case id, dayKey, sentence, translation, source, occasion, isAI, isManualSeed, savedAt
    }

    init(
        id: String = UUID().uuidString,
        dayKey: String,
        sentence: String,
        translation: String?,
        source: String?,
        occasion: String?,
        isAI: Bool,
        isManualSeed: Bool = false,
        savedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.dayKey = dayKey
        self.sentence = sentence
        self.translation = translation
        self.source = source
        self.occasion = occasion
        self.isAI = isAI
        self.isManualSeed = isManualSeed
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        sentence = try container.decode(String.self, forKey: .sentence)
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        occasion = try container.decodeIfPresent(String.self, forKey: .occasion)
        isAI = try container.decodeIfPresent(Bool.self, forKey: .isAI) ?? false
        isManualSeed = try container.decodeIfPresent(Bool.self, forKey: .isManualSeed) ?? false
        // Legacy rows used dayKey as identity; keep them readable after migration.
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? dayKey
        savedAt = try container.decodeIfPresent(Double.self, forKey: .savedAt) ?? 0
    }

    var displaySentence: String {
        LiteraryTextFormatting.display(sentence)
    }

    var displayTranslation: String? {
        guard let translation else { return nil }
        let formatted = LiteraryTextFormatting.display(translation)
        return formatted.isEmpty ? nil : formatted
    }

    var asReflection: DailyReflection {
        DailyReflection(
            sentence: sentence,
            translation: translation,
            source: source,
            occasion: occasion,
            isAI: isAI
        )
    }

    var displayDate: String {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return dayKey }
        return String(format: "%d月%d日", parts[1], parts[2])
    }
}

/// Timely line of the day: AI once per day (cached), curated fallback — never from the user's deck.
enum DailyReflectionService {
    private static let cacheDefaultsKey = "knowell.dailyReflection.v4"
    private static let historyDefaultsKey = "knowell.dailyReflection.history.v1"
    private static let restoreSummerFlowerKey = "knowell.dailyReflection.restore.summerFlower.v1"
    private static var inFlight: Task<DailyReflection, Never>?
    private static var inFlightDayKey: String?

    /// Instant: today's AI cache if any, otherwise curated (stable for the day).
    static func cachedOrCurated(for day: Date = .now) -> DailyReflection {
        seedManualPastLinesIfNeeded(relativeTo: day)
        restoreSummerFlowerLineIfNeeded(for: day)
        let key = dayKey(day)
        if let cached = loadCache(), cached.dayKey == key {
            let reflection = cached.asReflection(isAI: true)
            if isWellFormed(reflection) {
                archive(reflection, dayKey: key)
                return reflection
            }
        }
        let curated = curated(for: day)
        archive(curated, dayKey: key)
        return curated
    }

    /// Fetch a timely AI line at most once per calendar day; falls back to curated on failure.
    static func refreshIfNeeded(for day: Date = .now, options: FetchOptions = FetchOptions()) async -> DailyReflection {
        let key = dayKey(day)
        if !options.isManualRefresh,
           let cached = loadCache(), cached.dayKey == key {
            let reflection = cached.asReflection(isAI: true)
            if isWellFormed(reflection) {
                archive(reflection, dayKey: key)
                return reflection
            }
        }

        if let inFlight, inFlightDayKey == key, !options.isManualRefresh {
            return await inFlight.value
        }

        let task = Task<DailyReflection, Never> {
            await fetchAndPersist(for: day, dayKey: key, options: options)
        }
        inFlight = task
        inFlightDayKey = key
        let result = await task.value
        if inFlightDayKey == key {
            inFlight = nil
            inFlightDayKey = nil
        }
        return result
    }

    /// One-time: put back the Sonnet 94 line that was lost to an early refresh.
    private static func restoreSummerFlowerLineIfNeeded(for day: Date) {
        guard !UserDefaults.standard.bool(forKey: restoreSummerFlowerKey) else { return }
        let key = dayKey(day)
        let reflection = DailyReflection(
            sentence: "The summer's flower is to the summer sweet, Though to itself it only live and die.",
            translation: "夏日的花朵对夏日总是甜蜜，尽管对它自己它只自生自灭。",
            source: "Sonnet 94 · William Shakespeare",
            occasion: nil,
            isAI: true
        )
        archive(reflection, dayKey: key)
        saveCache(
            CachedReflection(
                dayKey: key,
                sentence: reflection.sentence,
                translation: reflection.translation,
                source: reflection.source,
                occasion: reflection.occasion
            )
        )
        UserDefaults.standard.set(true, forKey: restoreSummerFlowerKey)
    }

    /// Drop today's AI cache so the next refresh can pick up new preferences.
    static func invalidateTodayCache() {
        UserDefaults.standard.removeObject(forKey: cacheDefaultsKey)
        inFlight = nil
        inFlightDayKey = nil
    }

    /// Manual retry: keep the current line in history, then fetch a new one.
    static func refreshNow(
        replacing current: DailyReflection? = nil,
        for day: Date = .now
    ) async -> DailyReflection {
        let key = dayKey(day)
        if let current {
            archive(current, dayKey: key)
        } else if let cached = loadCache(), cached.dayKey == key {
            archive(cached.asReflection(isAI: true), dayKey: key)
        }
        invalidateTodayCache()

        let excluded = sentencesArchivedToday(dayKey: key)
        let options = FetchOptions(
            isManualRefresh: true,
            refreshAttempt: max(1, excluded.count),
            excludedSentences: excluded
        )
        return await refreshIfNeeded(for: day, options: options)
    }

    // MARK: - History

    private static let pastSeedDefaultsKey = "knowell.dailyReflection.history.pastSeed.v1"

    /// Newest first. Empty `query` returns the full archive.
    static func history(matching query: String = "") -> [ArchivedDailyReflection] {
        seedManualPastLinesIfNeeded()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = loadHistory().sorted {
            if $0.dayKey != $1.dayKey { return $0.dayKey > $1.dayKey }
            return $0.savedAt > $1.savedAt
        }
        guard !needle.isEmpty else { return items }
        return items.filter { item in
            item.sentence.lowercased().contains(needle)
                || (item.translation?.lowercased().contains(needle) ?? false)
                || (item.source?.lowercased().contains(needle) ?? false)
                || (item.occasion?.lowercased().contains(needle) ?? false)
                || item.dayKey.contains(needle)
        }
    }

    static var historyCount: Int {
        seedManualPastLinesIfNeeded()
        return loadHistory().count
    }

    /// Keep every distinct sentence for a day (refresh must not erase the previous line).
    static func archive(_ reflection: DailyReflection, for day: Date = .now) {
        seedManualPastLinesIfNeeded(relativeTo: day)
        archive(reflection, dayKey: dayKey(day))
    }

    private static func archive(_ reflection: DailyReflection, dayKey: String) {
        guard isWellFormed(reflection) else { return }
        var items = loadHistory()
        let normalized = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if items.contains(where: {
            $0.dayKey == dayKey
                && $0.sentence.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }) {
            return
        }
        // Don't let a curated flash append when an AI line already exists for the day.
        if !reflection.isAI, items.contains(where: { $0.dayKey == dayKey && $0.isAI }) {
            return
        }
        // Keep manually seeded past lines unless AI arrives for that day.
        if !reflection.isAI, items.contains(where: { $0.dayKey == dayKey && $0.isManualSeed }) {
            return
        }

        items.insert(
            ArchivedDailyReflection(
                dayKey: dayKey,
                sentence: reflection.sentence,
                translation: reflection.translation,
                source: reflection.source,
                occasion: reflection.occasion,
                isAI: reflection.isAI,
                isManualSeed: false
            ),
            at: 0
        )
        // Soft cap — keep about a year of daily lines (+ a few refreshes).
        if items.count > 500 {
            items = Array(
                items.sorted {
                    if $0.dayKey != $1.dayKey { return $0.dayKey > $1.dayKey }
                    return $0.savedAt > $1.savedAt
                }
                .prefix(500)
            )
        }
        saveHistory(items)
    }

    /// One-time: fill yesterday + day-before with chosen literary lines; later days append normally.
    private static func seedManualPastLinesIfNeeded(relativeTo day: Date = .now) {
        guard !UserDefaults.standard.bool(forKey: pastSeedDefaultsKey) else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard
            let yesterday = calendar.date(byAdding: .day, value: -1, to: start),
            let dayBefore = calendar.date(byAdding: .day, value: -2, to: start)
        else { return }

        forceUpsert(
            ArchivedDailyReflection(
                dayKey: dayKey(yesterday),
                sentence: "Whose woods these are I think I know.",
                translation: "我想我知道这些树林是谁的。",
                source: "Stopping by Woods on a Snowy Evening · Robert Frost（雪夜林边驻马）",
                occasion: nil,
                isAI: false,
                isManualSeed: true
            )
        )
        forceUpsert(
            ArchivedDailyReflection(
                dayKey: dayKey(dayBefore),
                sentence: "Summer afternoon—summer afternoon; to me those have always been the two most beautiful words in the English language.",
                translation: "夏日午后——夏日午后，于我而言始终是英文里最美的两个词。",
                source: "Henry James（亨利·詹姆斯）",
                occasion: nil,
                isAI: false,
                isManualSeed: true
            )
        )
        UserDefaults.standard.set(true, forKey: pastSeedDefaultsKey)
    }

    private static func forceUpsert(_ item: ArchivedDailyReflection) {
        var items = loadHistoryRaw()
        if let index = items.firstIndex(where: { $0.dayKey == item.dayKey && $0.isManualSeed }) {
            items[index] = item
        } else if let index = items.firstIndex(where: { $0.dayKey == item.dayKey }) {
            items[index] = item
        } else {
            items.append(item)
        }
        saveHistory(items)
    }

    private static func loadHistory() -> [ArchivedDailyReflection] {
        seedManualPastLinesIfNeeded()
        return loadHistoryRaw()
    }

    private static func loadHistoryRaw() -> [ArchivedDailyReflection] {
        guard let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
              let items = try? JSONDecoder().decode([ArchivedDailyReflection].self, from: data) else {
            return seedHistoryFromTodayCacheIfNeeded()
        }
        return items
    }

    private static func saveHistory(_ items: [ArchivedDailyReflection]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: historyDefaultsKey)
    }

    private static func seedHistoryFromTodayCacheIfNeeded() -> [ArchivedDailyReflection] {
        guard let cached = loadCache() else { return [] }
        let seeded = [
            ArchivedDailyReflection(
                dayKey: cached.dayKey,
                sentence: cached.sentence,
                translation: cached.translation,
                source: cached.source,
                occasion: cached.occasion,
                isAI: true,
                isManualSeed: false
            )
        ]
        saveHistory(seeded)
        return seeded
    }

    // MARK: - AI

    struct FetchOptions {
        var isManualRefresh = false
        var refreshAttempt = 1
        var excludedSentences: [String] = []
        var excludedSources: [String] = []
        var dailyAngle: String?
    }

    private static let recentDedupDays = 14

    /// Rotate the reading lens each day so the same 3 keywords don't collapse onto one famous line.
    private static let dailyAngles: [String] = [
        "开篇：选作品开头最能立住气质的一句",
        "口吻：选一句能听出说话人性格的台词或旁白",
        "景物：写景或物象，但不堆砌季节词",
        "关系：人与人之间的一句（相遇、离别、对峙）",
        "记忆：关于时间、过去或逝去的一句",
        "决意：正在做或将要做的一句",
        "机锋：克制的反讽或冷幽默，不要段子",
        "收束：章节或作品近结尾、有余味的一句",
        "意象：用一个具体物象撑起的一句",
        "独白：不喊口号的自我省察",
        "闲笔：对话或叙述里看似最轻、实有分量的一句",
        "旅途：在路上、异乡或逆旅中的一句"
    ]

    private static func dailyAngle(for day: Date, refreshAttempt: Int) -> String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 1
        let index = abs(dayOfYear + max(0, refreshAttempt - 1) * 3) % dailyAngles.count
        return dailyAngles[index]
    }

    private static func recentExclusion(for day: Date, extraSentences: [String] = []) -> (sentences: [String], sources: [String]) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let minKey: String
        if let windowStart = calendar.date(byAdding: .day, value: -(recentDedupDays - 1), to: start) {
            minKey = dayKey(windowStart)
        } else {
            minKey = dayKey(day)
        }
        let todayKey = dayKey(day)

        var sentenceSeen = Set<String>()
        var sentences: [String] = []
        for sentence in extraSentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if sentenceSeen.insert(normalizedSentenceKey(trimmed)).inserted {
                sentences.append(trimmed)
            }
        }

        var sourceSeen = Set<String>()
        var sources: [String] = []

        for item in loadHistoryRaw() where item.dayKey >= minKey && item.dayKey <= todayKey {
            let sentence = item.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty, sentenceSeen.insert(normalizedSentenceKey(sentence)).inserted {
                sentences.append(sentence)
            }
            if let source = item.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty,
               sourceSeen.insert(source.lowercased()).inserted {
                sources.append(source)
            }
        }
        return (sentences, sources)
    }

    private static func sentencesArchivedToday(dayKey: String) -> [String] {
        seedManualPastLinesIfNeeded()
        var seen = Set<String>()
        return loadHistoryRaw()
            .filter { $0.dayKey == dayKey }
            .sorted { $0.savedAt > $1.savedAt }
            .compactMap { item -> String? in
                let sentence = item.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentence.isEmpty else { return nil }
                let key = normalizedSentenceKey(sentence)
                guard seen.insert(key).inserted else { return nil }
                return sentence
            }
    }

    private static func normalizedSentenceKey(_ sentence: String) -> String {
        sentence
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isDuplicateSentence(_ sentence: String, excluded: [String]) -> Bool {
        let key = normalizedSentenceKey(sentence)
        return excluded.contains { normalizedSentenceKey($0) == key }
    }

    private static func fetchAndPersist(for day: Date, dayKey key: String, options: FetchOptions) async -> DailyReflection {
        var options = options
        let recent = recentExclusion(for: day, extraSentences: options.excludedSentences)
        options.excludedSentences = recent.sentences
        options.excludedSources = recent.sources
        if options.dailyAngle == nil {
            options.dailyAngle = dailyAngle(for: day, refreshAttempt: options.refreshAttempt)
        }

        let fallback = curated(for: day, variantOffset: options.isManualRefresh ? options.refreshAttempt : 0)

        guard APISettings.canUseAI else {
            archive(fallback, dayKey: key)
            return fallback
        }

        let attempts = options.excludedSentences.isEmpty ? (options.isManualRefresh ? 2 : 1) : 2
        for attempt in 0..<attempts {
            do {
                let ai = try await fetchAIReflection(
                    for: day,
                    options: options,
                    retryBoost: attempt > 0
                )
                guard isWellFormed(ai) else { continue }
                guard !isDuplicateSentence(ai.sentence, excluded: options.excludedSentences) else {
                    continue
                }
                saveCache(CachedReflection(
                    dayKey: key,
                    sentence: ai.sentence,
                    translation: ai.translation,
                    source: ai.source,
                    occasion: ai.occasion
                ))
                archive(ai, dayKey: key)
                return ai
            } catch {
                continue
            }
        }

        archive(fallback, dayKey: key)
        return fallback
    }

    private static func fetchAIReflection(
        for day: Date,
        options: FetchOptions = FetchOptions(),
        retryBoost: Bool = false
    ) async throws -> DailyReflection {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APISettings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        applyProviderHeaders(to: &request)

        let dateText = day.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Locale(identifier: "zh_CN")))
        let season = northernSeasonName(for: day)
        let localeID = Locale.current.identifier

        let systemPrompt = """
        你是克制的阅读陪伴助手，为学习 App「致知」挑选「今日一句」。
        只返回 JSON，不要 markdown，不要代码块，不要任何字段外的说明文字。

        格式：
        {
          "sentence": "原文（作品本来的语言与写法）",
          "translation": "中文翻译；原文已是现代汉语则必须空字符串",
          "source": "与 sentence 同语言的出处；不确定则空字符串",
          "source_zh": "sentence 为外文/文言时的中文出处；现代汉语原文可空字符串",
          "occasion": "极短缘由；没有则空字符串，最多 12 字"
        }

        【格式禁令 — 违反任一条视为无效输出】
        1. 禁止用斜杠 / 表示换行、分隔、占位或「或者」；sentence 与 translation 内不得出现 /
        2. 禁止把 \\n、/n 当作文字写进 sentence 或 translation；需要换行时在 JSON 字符串里写真实换行符
        3. 禁止 markdown（**、__、#、```、>）及 HTML 标签
        4. 禁止竖线 |、制表符、多余空行、首尾空格
        5. 禁止在 sentence/translation 里写出处；出处只放在 source / source_zh
        6. 禁止把翻译放进 sentence，或把外文原文只放在 translation

        【换行 — 何时用、何时不用】
        - 默认：sentence 与 translation 都是单行字符串，不含换行符
        - 仅当原文本身是短诗、且分行是作品固有形式时，才在 JSON 内用真实换行
        - 散文、戏剧台词、哲言、小说摘录：即使出自 blank verse，也写成一整句，不要人为拆行
        - 禁止为排版把句中词拆到新行；禁止因换行把句中 as/is/and 等改成行首大写

        【诗歌换行 — 仅短诗可用】
        - 正确（两行诗，分行是作品形式）：
          "sentence": "The world is too much with us; late and soon,\\nGetting and spending, we lay waste our powers;—"
        - 正确（散文/戏剧，单行）：
          "sentence": "We are such stuff as dreams are made on, and our little life is rounded with a sleep."
        - 错误（禁止人为诗化散文）：把上一句拆成三行且 As/Is 大写
        - 错误（禁止）："……soon, / Getting……" 或 "……早晚，/ 获取……"

        【出处 — 正确做法】
        - 外文原文：source 用外文（如 William Wordsworth, The World Is Too Much With Us），source_zh 用中文
        - 中文原文：source 用中文（如《论语·为政》），source_zh 留空

        选句优先级：浪漫、哲理、智慧 > 文学质地 > 季节点缀（季节不得主导选句）

        其他规则：
        1. sentence 必须是可核对的原文，不超过约 120 字符
        2. 现代汉语原文：translation 与 source_zh 留空
        3. source / source_zh 无把握则空字符串，禁止编造
        4. 不要鸡汤口号、不要催学习、不要广告
        5. 连续多日必须换作品（或同一作家的另一部作品），并换切入角度；禁止连续使用同一原文
        6. 用户关键词是气质/口味，不是必须写进句子的字；禁止为了贴关键词而选最烂熟的那一句
        """

        let preferenceHint: String
        if let snippet = DailyReflectionPreferences.promptSnippet {
            let languageLock: String
            switch DailyReflectionPreferences.originalLanguageBias {
            case .chinese:
                languageLock = """
                【原文语言 — 必须遵守】
                用户口味是中文语境。sentence 必须是中文原文（白话、文言或小说原文），禁止用英文/法文等外文原句再配翻译来凑这一口味。
                原文已是现代汉语：translation 留空。文言可给一句极短白话，也可留空。
                """
            case .english:
                languageLock = """
                【原文语言 — 必须遵守】
                用户口味偏英文。sentence 必须是英文（或作品原来的西文）原文，并给出中文 translation。
                """
            case .unspecified:
                languageLock = "原文语言跟随作品本身；不要为了换作品而跳出用户口味的语言世界。"
            }
            preferenceHint = """
            用户口味关键词：\(snippet)。这是选书/选作者的气质，不是造句素材。
            \(languageLock)
            - 从符合这一气质的作家或作品里选一句可核对的原文
            - 禁止把关键词塞进句子，禁止每天都用同一部代表作里最著名的那一句
            - 今天必须换一部与近期不同的作品；同一作家可以，但要换篇
            - 「换作品」只在同一语言/文化圈内换，不要从古龙跳到法国随笔
            """
        } else {
            preferenceHint = "用户未设置口味关键词。按默认优先级选句，今天仍须换作品、换角度。"
        }

        let angle = options.dailyAngle ?? dailyAngle(for: day, refreshAttempt: options.refreshAttempt)
        let excludedSentences = options.excludedSentences
        let excludedSources = options.excludedSources
        let exclusionBlock: String = {
            if excludedSentences.isEmpty && excludedSources.isEmpty {
                return "近期尚无已展示句子。"
            }
            var lines: [String] = []
            if !excludedSentences.isEmpty {
                lines.append("近期已展示原文（禁止重复）：")
                lines.append(contentsOf: excludedSentences.prefix(12).enumerated().map { index, sentence in
                    let preview = sentence.replacingOccurrences(of: "\n", with: " ")
                    let clipped = preview.count > 72 ? String(preview.prefix(72)) + "…" : preview
                    return "\(index + 1). \(clipped)"
                })
            }
            if !excludedSources.isEmpty {
                lines.append("近期出处（今天请换作品）：")
                lines.append(contentsOf: excludedSources.prefix(8).map { "- \($0)" })
            }
            return lines.joined(separator: "\n")
        }()

        let refreshHint: String
        if options.isManualRefresh {
            refreshHint = """
            这是用户第 \(options.refreshAttempt) 次刷新今日一句：必须换一句与下方列表完全不同的经典名句。
            禁止重复同一原文（不要只改 translation/source）；必须换作品，并换切入角度。
            今天切入角度：\(angle)
            \(exclusionBlock)
            """
        } else {
            refreshHint = """
            这是今日首次生成。必须与近期已展示原文完全不同，并换一部作品。
            今天切入角度：\(angle)
            \(exclusionBlock)
            """
        }

        let userPrompt = """
        今天：\(dateText)
        大致季节（仅供参考，优先级低）：\(season)
        用户地区标识：\(localeID)
        \(preferenceHint)
        \(refreshHint)

        请给出今日一句。要求：
        - 按今天的切入角度选一句可核对的原文；需要时再给中文翻译
        - 必须换一部与近期不同的作品，不要回到最著名的那一句
        - 默认单行输出；只有短诗且分行是原文形式时才用真实换行，散文/戏剧台词不要拆行
        - 外文必须同时给出外文 source 与中文 source_zh
        - 季节不必强行呼应
        """

        let preferredTemperature: Double
        if options.isManualRefresh {
            preferredTemperature = retryBoost ? 1.0 : 0.92
        } else if retryBoost || DailyReflectionPreferences.hasKeywords {
            preferredTemperature = 0.85
        } else {
            preferredTemperature = 0.7
        }
        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": APISettings.chatTemperature(preferred: preferredTemperature),
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw KimiCardGeneratorError.invalidResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw KimiCardGeneratorError.invalidResponse
        }

        return try parseAIReflection(from: content)
    }

    private static func parseAIReflection(from content: String) throws -> DailyReflection {
        let trimmed = extractJSONObject(from: content)
        guard let data = trimmed.data(using: .utf8) else {
            throw KimiCardGeneratorError.parseError("empty")
        }
        let decoded = try JSONDecoder().decode(AIReflectionDTO.self, from: data)
        let rawSentence = decoded.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTranslation = decoded.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
        if LiteraryTextFormatting.containsInvalidMarkers(rawSentence) {
            throw KimiCardGeneratorError.parseError("invalid-formatting")
        }
        if let rawTranslation, !rawTranslation.isEmpty,
           LiteraryTextFormatting.containsInvalidMarkers(rawTranslation) {
            throw KimiCardGeneratorError.parseError("invalid-formatting")
        }

        var sentence = LiteraryTextFormatting.display(rawSentence)
        guard !sentence.isEmpty, sentence.count <= 240 else {
            throw KimiCardGeneratorError.parseError("bad sentence")
        }
        var translation = rawTranslation
        if let rawTranslation, !rawTranslation.isEmpty {
            translation = LiteraryTextFormatting.display(rawTranslation)
        }
        if translation?.isEmpty == true {
            translation = nil
        }

        // Model sometimes swaps fields — keep authentic original in `sentence`.
        let normalized = normalizeOriginalFirst(sentence: sentence, translation: translation)
        sentence = normalized.sentence
        translation = normalized.translation

        // Modern Chinese original should not carry a redundant "translation".
        if latinLetterCount(sentence) < 4,
           hanCount(sentence) >= 4,
           let existingTranslation = translation,
           latinLetterCount(existingTranslation) < 4,
           hanCount(existingTranslation) >= 4,
           existingTranslation == sentence {
            translation = nil
        }

        let source = mergeSourceFields(primary: decoded.source, chinese: decoded.source_zh)
        let occasion = decoded.occasion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reflection = DailyReflection(
            sentence: sentence,
            translation: translation,
            source: source,
            occasion: (occasion?.isEmpty == false) ? String(occasion!.prefix(16)) : nil,
            isAI: true
        )
        guard isWellFormed(reflection) else {
            throw KimiCardGeneratorError.parseError("empty-original")
        }
        return reflection
    }

    private static func mergeSourceFields(primary: String?, chinese: String?) -> String? {
        let primaryText = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chineseText = chinese?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrimary = primaryText.map { !$0.isEmpty } ?? false
        let hasChinese = chineseText.map { !$0.isEmpty } ?? false
        if hasPrimary, hasChinese {
            return "\(primaryText!) | \(chineseText!)"
        }
        if hasPrimary { return primaryText }
        if hasChinese { return chineseText }
        return nil
    }

    /// Put authentic original in `sentence`; Chinese rendering in `translation` when needed.
    private static func normalizeOriginalFirst(sentence: String, translation: String?) -> (sentence: String, translation: String?) {
        guard let translation, !translation.isEmpty else {
            return (sentence, nil)
        }
        let sentenceLatin = latinLetterCount(sentence)
        let translationLatin = latinLetterCount(translation)
        // Chinese parked in sentence, foreign parked in translation → swap back to original-first.
        if sentenceLatin < 4, translationLatin >= 4 {
            return (translation, sentence)
        }
        return (sentence, translation)
    }

    private static func isWellFormed(_ reflection: DailyReflection) -> Bool {
        !reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count
    }

    private static func hanCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
    }

    private static func extractJSONObject(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    private static func applyProviderHeaders(to request: inout URLRequest) {
        switch APISettings.effectiveProvider {
        case .openrouter:
            request.setValue("https://knowell.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("KnoWell", forHTTPHeaderField: "X-Title")
        case .moonshot, .openai, .deepseek, .custom:
            break
        }
    }

    private static func northernSeasonName(for day: Date) -> String {
        let month = Calendar.current.component(.month, from: day)
        switch month {
        case 3, 4, 5: return "春"
        case 6, 7, 8: return "夏"
        case 9, 10, 11: return "秋"
        default: return "冬"
        }
    }

    // MARK: - Cache

    private struct CachedReflection: Codable {
        let dayKey: String
        let sentence: String
        let translation: String?
        let source: String?
        let occasion: String?

        func asReflection(isAI: Bool) -> DailyReflection {
            DailyReflection(
                sentence: sentence,
                translation: translation,
                source: source,
                occasion: occasion,
                isAI: isAI
            )
        }
    }

    private struct AIReflectionDTO: Decodable {
        let sentence: String
        let translation: String?
        let source: String?
        let source_zh: String?
        let occasion: String?
    }

    private static func dayKey(_ day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func loadCache() -> CachedReflection? {
        guard let data = UserDefaults.standard.data(forKey: cacheDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CachedReflection.self, from: data)
    }

    private static func saveCache(_ value: CachedReflection) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: cacheDefaultsKey)
    }

    // MARK: - Curated fallback

    private static func curated(for day: Date, variantOffset: Int = 0) -> DailyReflection {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let base = abs((comps.year ?? 0) * 372 + (comps.month ?? 0) * 31 + (comps.day ?? 0))
        let index = (base + max(0, variantOffset)) % curatedReflections.count
        let item = curatedReflections[index]
        return DailyReflection(
            sentence: item.sentence,
            translation: item.translation,
            source: item.source,
            occasion: item.occasion,
            isAI: false
        )
    }

    private static let curatedReflections: [DailyReflection] = [
        DailyReflection(
            sentence: "知之为知之，不知为不知，是知也。",
            translation: "知道就是知道，不知道就是不知道，这才是真正的知。",
            source: "《论语·为政》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "吾生也有涯，而知也无涯。",
            translation: "生命有尽头，而求知没有尽头。",
            source: "《庄子·养生主》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "路漫漫其修远兮，吾将上下而求索。",
            translation: "道路漫长又遥远，我将上上下下地追寻。",
            source: "屈原《离骚》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "博学之，审问之，慎思之，明辨之，笃行之。",
            translation: "广泛地学习，详细地询问，慎重地思考，清楚地辨别，切实地实行。",
            source: "《中庸》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "学而不思则罔，思而不学则殆。",
            translation: "只学习不思考会迷茫，只思考不学习会危险。",
            source: "《论语·为政》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "静以修身，俭以养德。",
            translation: "以宁静修养自身，以节俭涵养品德。",
            source: "诸葛亮《诫子书》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The only true wisdom is in knowing you know nothing.",
            translation: "真正的智慧，在于知道自己一无所知。",
            source: "Socrates",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            translation: "我们反复做的事成就了我们。因此卓越不是一次举动，而是一种习惯。",
            source: "Will Durant (on Aristotle)",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The unexamined life is not worth living.",
            translation: "未经省察的人生不值得过。",
            source: "Plato, Apology",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The important thing is not to stop questioning.",
            translation: "重要的是不要停止提问。",
            source: "Albert Einstein",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "Reading is to the mind what exercise is to the body.",
            translation: "阅读之于心灵，犹如运动之于身体。",
            source: "Joseph Addison",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "Someone's sitting in the shade today because someone planted a tree a long time ago.",
            translation: "有人今天能坐在树荫下，是因为很久以前有人栽下了一棵树。",
            source: "Warren Buffett",
            occasion: nil,
            isAI: false
        )
    ]
}
