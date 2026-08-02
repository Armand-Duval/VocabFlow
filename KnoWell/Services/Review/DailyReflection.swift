import Foundation

/// A gentle daily sentence for the review-home “done” state.
struct DailyReflection: Equatable {
    let sentence: String
    let source: String?
    /// Optional short seasonal / cultural note (e.g. “立秋将近”), never required.
    let occasion: String?
    /// True when produced by AI for the calendar day (vs curated fallback).
    let isAI: Bool
}

/// Timely line of the day: AI once per day (cached), curated fallback — never from the user's deck.
enum DailyReflectionService {
    private static let cacheDefaultsKey = "knowell.dailyReflection.v1"
    private static var inFlight: Task<DailyReflection, Never>?
    private static var inFlightDayKey: String?

    /// Instant: today's AI cache if any, otherwise curated (stable for the day).
    static func cachedOrCurated(for day: Date = .now) -> DailyReflection {
        let key = dayKey(day)
        if let cached = loadCache(), cached.dayKey == key {
            return cached.asReflection(isAI: true)
        }
        return curated(for: day)
    }

    /// Fetch a timely AI line at most once per calendar day; falls back to curated on failure.
    static func refreshIfNeeded(for day: Date = .now) async -> DailyReflection {
        let key = dayKey(day)
        if let cached = loadCache(), cached.dayKey == key {
            return cached.asReflection(isAI: true)
        }

        if let inFlight, inFlightDayKey == key {
            return await inFlight.value
        }

        let task = Task<DailyReflection, Never> {
            guard APISettings.canUseAI else {
                return curated(for: day)
            }
            do {
                let ai = try await fetchAIReflection(for: day)
                saveCache(CachedReflection(
                    dayKey: key,
                    sentence: ai.sentence,
                    source: ai.source,
                    occasion: ai.occasion
                ))
                return ai
            } catch {
                return curated(for: day)
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
          "sentence": "一句优美或有哲理的完整句子（中文或英文皆可，偏短，不超过 80 字）",
          "source": "可核对的出处（书名/篇章/作者；不确定必须空字符串）",
          "occasion": "与今日相关的极短缘由（如节气、季节、常见节日；没有则空字符串，最多 12 字）"
        }
        规则：
        1. 句子要适合安静阅读，有回味，不要鸡汤口号、不要催学习、不要广告
        2. 可轻应景：日期、季节、节气、广为人知的节日；不要编造冷门「历史上的今天」或虚假纪念日
        3. source 必须真实可指认；无把握就返回空字符串，禁止编造书名/作者
        4. 不要输出多句，不要解释
        """

        let userPrompt = """
        今天：\(dateText)
        大致季节：\(season)
        用户地区标识：\(localeID)
        请给出一句合时宜的今日一句。
        """

        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
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
        let sentence = decoded.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, sentence.count <= 200 else {
            throw KimiCardGeneratorError.parseError("bad sentence")
        }
        let source = decoded.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let occasion = decoded.occasion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DailyReflection(
            sentence: sentence,
            source: (source?.isEmpty == false) ? source : nil,
            occasion: (occasion?.isEmpty == false) ? String(occasion!.prefix(16)) : nil,
            isAI: true
        )
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
        let source: String?
        let occasion: String?

        func asReflection(isAI: Bool) -> DailyReflection {
            DailyReflection(sentence: sentence, source: source, occasion: occasion, isAI: isAI)
        }
    }

    private struct AIReflectionDTO: Decodable {
        let sentence: String
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
        var item = curatedReflections[seed % curatedReflections.count]
        // Curated entries are stored with isAI false.
        item = DailyReflection(
            sentence: item.sentence,
            source: item.source,
            occasion: item.occasion,
            isAI: false
        )
        return item
    }

    private static let curatedReflections: [DailyReflection] = [
        DailyReflection(
            sentence: "知之为知之，不知为不知，是知也。",
            source: "《论语·为政》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "吾生也有涯，而知也无涯。",
            source: "《庄子·养生主》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "路漫漫其修远兮，吾将上下而求索。",
            source: "屈原《离骚》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "博学之，审问之，慎思之，明辨之，笃行之。",
            source: "《中庸》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "学而不思则罔，思而不学则殆。",
            source: "《论语·为政》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "静以修身，俭以养德。",
            source: "诸葛亮《诫子书》",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The only true wisdom is in knowing you know nothing.",
            source: "Socrates",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            source: "Will Durant (on Aristotle)",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The unexamined life is not worth living.",
            source: "Plato, Apology",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "The important thing is not to stop questioning.",
            source: "Albert Einstein",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "Reading is to the mind what exercise is to the body.",
            source: "Joseph Addison",
            occasion: nil,
            isAI: false
        ),
        DailyReflection(
            sentence: "Someone's sitting in the shade today because someone planted a tree a long time ago.",
            source: "Warren Buffett",
            occasion: nil,
            isAI: false
        )
    ]
}
