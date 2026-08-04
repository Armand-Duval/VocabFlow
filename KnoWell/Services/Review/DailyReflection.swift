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
}

/// One calendar day's reflection kept for later browsing (local archive).
struct ArchivedDailyReflection: Identifiable, Equatable, Codable {
    var id: String { dayKey }
    let dayKey: String
    let sentence: String
    let translation: String?
    let source: String?
    let occasion: String?
    let isAI: Bool
    /// Hand-picked seed for a past day; protected from curated overwrite.
    var isManualSeed: Bool

    enum CodingKeys: String, CodingKey {
        case dayKey, sentence, translation, source, occasion, isAI, isManualSeed
    }

    init(
        dayKey: String,
        sentence: String,
        translation: String?,
        source: String?,
        occasion: String?,
        isAI: Bool,
        isManualSeed: Bool = false
    ) {
        self.dayKey = dayKey
        self.sentence = sentence
        self.translation = translation
        self.source = source
        self.occasion = occasion
        self.isAI = isAI
        self.isManualSeed = isManualSeed
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
    private static var inFlight: Task<DailyReflection, Never>?
    private static var inFlightDayKey: String?

    /// Instant: today's AI cache if any, otherwise curated (stable for the day).
    static func cachedOrCurated(for day: Date = .now) -> DailyReflection {
        seedManualPastLinesIfNeeded(relativeTo: day)
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
    static func refreshIfNeeded(for day: Date = .now) async -> DailyReflection {
        let key = dayKey(day)
        let fallback = curated(for: day)
        if let cached = loadCache(), cached.dayKey == key {
            let reflection = cached.asReflection(isAI: true)
            if isWellFormed(reflection) {
                archive(reflection, dayKey: key)
                return reflection
            }
        }

        if let inFlight, inFlightDayKey == key {
            return await inFlight.value
        }

        let task = Task<DailyReflection, Never> {
            guard APISettings.canUseAI else {
                archive(fallback, dayKey: key)
                return fallback
            }
            do {
                let ai = try await fetchAIReflection(for: day)
                guard isWellFormed(ai) else {
                    archive(fallback, dayKey: key)
                    return fallback
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
                archive(fallback, dayKey: key)
                return fallback
            }
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

    // MARK: - History

    private static let pastSeedDefaultsKey = "knowell.dailyReflection.history.pastSeed.v1"

    /// Newest first. Empty `query` returns the full archive.
    static func history(matching query: String = "") -> [ArchivedDailyReflection] {
        seedManualPastLinesIfNeeded()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = loadHistory().sorted { $0.dayKey > $1.dayKey }
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

    /// Upsert one day. Prefer AI over curated when replacing the same day.
    static func archive(_ reflection: DailyReflection, for day: Date = .now) {
        seedManualPastLinesIfNeeded(relativeTo: day)
        archive(reflection, dayKey: dayKey(day))
    }

    private static func archive(_ reflection: DailyReflection, dayKey: String) {
        guard isWellFormed(reflection) else { return }
        var items = loadHistory()
        if let index = items.firstIndex(where: { $0.dayKey == dayKey }) {
            let existing = items[index]
            // Don't let a curated flash overwrite a stored AI line for the same day.
            if existing.isAI, !reflection.isAI { return }
            // Keep manually seeded past lines unless AI arrives for that day.
            if existing.isManualSeed, !reflection.isAI { return }
            items[index] = ArchivedDailyReflection(
                dayKey: dayKey,
                sentence: reflection.sentence,
                translation: reflection.translation,
                source: reflection.source,
                occasion: reflection.occasion,
                isAI: reflection.isAI,
                isManualSeed: false
            )
        } else {
            items.append(
                ArchivedDailyReflection(
                    dayKey: dayKey,
                    sentence: reflection.sentence,
                    translation: reflection.translation,
                    source: reflection.source,
                    occasion: reflection.occasion,
                    isAI: reflection.isAI,
                    isManualSeed: false
                )
            )
        }
        // Soft cap — keep about a year of daily lines.
        if items.count > 400 {
            items = Array(items.sorted { $0.dayKey > $1.dayKey }.prefix(400))
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
        if let index = items.firstIndex(where: { $0.dayKey == item.dayKey }) {
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

    private static func fetchAIReflection(for day: Date) async throws -> DailyReflection {
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
        只返回 JSON，不要 markdown。
        格式：
        {
          "sentence": "原文（作品本来的语言与写法，原汁原味；可以是外文、文言，也可以是现代汉语）",
          "translation": "中文翻译或白话；仅当原文不是现代汉语时填写；原文已是现代汉语则必须空字符串",
          "source": "可核对的出处（书名/篇章/作者；不确定必须空字符串）",
          "occasion": "与今日相关的极短缘由（如节气、季节、常见节日；没有则空字符串，最多 12 字）"
        }
        规则：
        1. sentence 必须是原文本身，不要用翻译顶替原文
        2. 外文/文言：sentence=原文，translation=中文；现代汉语原文：sentence=原文，translation 留空
        3. 禁止：把外文译成中文后只把中文放进 sentence（丢掉外文原文）
        4. 不要对调字段；读者先看到 sentence，再看到 translation
        5. 句子要适合安静阅读，有回味，不要鸡汤口号、不要催学习、不要广告；原文偏短（不超过约 120 字符）
        6. 可轻应景：日期、季节、节气、广为人知的节日；不要编造冷门「历史上的今天」或虚假纪念日
        7. source 必须真实可指认；无把握就返回空字符串，禁止编造书名/作者
        8. 不要输出多句，不要解释
        """

        let userPrompt = """
        今天：\(dateText)
        大致季节：\(season)
        用户地区标识：\(localeID)
        请给出一句合时宜的今日一句：保留原汁原味的原文；需要时再给中文翻译。
        """

        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": APISettings.chatTemperature(preferred: 0.7),
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
        var sentence = decoded.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, sentence.count <= 240 else {
            throw KimiCardGeneratorError.parseError("bad sentence")
        }
        var translation = decoded.translation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        let source = decoded.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let occasion = decoded.occasion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reflection = DailyReflection(
            sentence: sentence,
            translation: translation,
            source: (source?.isEmpty == false) ? source : nil,
            occasion: (occasion?.isEmpty == false) ? String(occasion!.prefix(16)) : nil,
            isAI: true
        )
        guard isWellFormed(reflection) else {
            throw KimiCardGeneratorError.parseError("empty-original")
        }
        return reflection
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

    private static func curated(for day: Date) -> DailyReflection {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let seed = abs((comps.year ?? 0) * 372 + (comps.month ?? 0) * 31 + (comps.day ?? 0))
        let item = curatedReflections[seed % curatedReflections.count]
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
