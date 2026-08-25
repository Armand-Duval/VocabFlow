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

    /// Newest first. Empty `query` returns the full archive.
    static func history(matching query: String = "") -> [ArchivedDailyReflection] {
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
        loadHistory().count
    }

    /// Keep every distinct sentence for a day (refresh must not erase the previous line).
    static func archive(_ reflection: DailyReflection, for day: Date = .now) {
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

    private static func loadHistory() -> [ArchivedDailyReflection] {
        loadHistoryRaw()
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
    }

    private static let recentDedupDays = 45

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
        let lowered = sentence.lowercased()
        let kept = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(kept))
    }

    private static func isDuplicateSentence(_ sentence: String, excluded: [String]) -> Bool {
        let key = normalizedSentenceKey(sentence)
        guard key.count >= 8 else { return false }
        return excluded.contains { other in
            let otherKey = normalizedSentenceKey(other)
            guard otherKey.count >= 8 else { return false }
            if otherKey == key { return true }
            if key.count >= 12, otherKey.count >= 12 {
                return key.contains(otherKey) || otherKey.contains(key)
            }
            return false
        }
    }

    private static func fetchAndPersist(for day: Date, dayKey key: String, options: FetchOptions) async -> DailyReflection {
        var options = options
        let recent = recentExclusion(for: day, extraSentences: options.excludedSentences)
        options.excludedSentences = recent.sentences
        options.excludedSources = recent.sources

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
            throw CardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        APISettings.applyChatHeaders(to: &request)

        let prompt = DailyReflectionPrompt.Input(
            dateText: day.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(Locale(identifier: "zh_CN"))),
            day: day,
            localeID: Locale.current.identifier,
            preferenceSnippet: DailyReflectionPreferences.promptSnippet,
            excludedSentences: options.excludedSentences,
            excludedSources: options.excludedSources,
            isManualRefresh: options.isManualRefresh,
            refreshAttempt: options.refreshAttempt,
            retryBoost: retryBoost
        )
        let systemPrompt = DailyReflectionPrompt.system
        let userPrompt = DailyReflectionPrompt.user(prompt)
        let preferredTemperature = DailyReflectionPrompt.preferredTemperature(prompt)
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
        guard let http = response as? HTTPURLResponse else {
            throw CardGeneratorError.invalidResponse
        }
        CloudAIQuota.ingest(http: http, data: data)
        guard http.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if let message = CloudAIQuota.mappedMessage(statusCode: http.statusCode, raw: raw) {
                throw CardGeneratorError.apiError(message)
            }
            throw CardGeneratorError.invalidResponse
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw CardGeneratorError.invalidResponse
        }

        return try parseAIReflection(from: content)
    }

    private static func parseAIReflection(from content: String) throws -> DailyReflection {
        let trimmed = AIJSON.extractObject(from: content)
        guard let data = trimmed.data(using: .utf8) else {
            throw CardGeneratorError.parseError("empty")
        }
        let decoded = try JSONDecoder().decode(AIReflectionDTO.self, from: data)
        let rawSentence = decoded.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTranslation = decoded.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
        if LiteraryTextFormatting.containsInvalidMarkers(rawSentence) {
            throw CardGeneratorError.parseError("invalid-formatting")
        }
        if let rawTranslation, !rawTranslation.isEmpty,
           LiteraryTextFormatting.containsInvalidMarkers(rawTranslation) {
            throw CardGeneratorError.parseError("invalid-formatting")
        }

        var sentence = LiteraryTextFormatting.display(rawSentence)
        guard !sentence.isEmpty, sentence.count <= 240 else {
            throw CardGeneratorError.parseError("bad sentence")
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
            throw CardGeneratorError.parseError("empty-original")
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
        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return false }
        if isForeignOriginal(sentence) {
            let translation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translation.isEmpty, hanCount(translation) >= 2 else { return false }
            let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard hanCount(source) >= 2 else { return false }
        }
        return true
    }

    private static func isForeignOriginal(_ text: String) -> Bool {
        latinLetterCount(text) >= 4 && latinLetterCount(text) > hanCount(text)
    }

    private static func latinLetterCount(_ text: String) -> Int {
        LiteraryTextFormatting.latinLetterCount(text)
    }

    private static func hanCount(_ text: String) -> Int {
        LiteraryTextFormatting.hanCount(text)
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
