import Foundation

enum KimiCardGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            L10n.missingAPIKeyError
        case .invalidResponse:
            String(localized: "error.invalidResponse")
        case .apiError(let message):
            message
        case .parseError(let message):
            L10n.parseError(message)
        }
    }
}

enum KimiCardGenerator {
    static func generate(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        deckName: String? = nil
    ) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseAI else {
            throw KimiCardGeneratorError.missingAPIKey
        }

        let units = generationUnits(sentence: sentence, words: words)
        guard !units.isEmpty else { return [] }
        let hint = sourceHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let deck = usefulDeckName(deckName)

        // One API call per sentence-context so each card front stays that word's sentence only.
        var allDrafts: [GeneratedCardDraft] = []
        for unit in units {
            let drafts = try await generateForSingleContext(
                sentence: unit.sentence,
                words: unit.words,
                sourceHint: hint,
                deckName: deck
            )
            allDrafts.append(contentsOf: drafts)
        }
        return allDrafts
    }

    /// Skip generic default decks — they add noise, not context.
    static func usefulDeckName(_ raw: String?) -> String? {
        let name = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        guard let name else { return nil }
        let defaults: Set<String> = [
            L10n.deckDefaultName,
            "默认词库",
            "Default",
            "Default Deck"
        ]
        if defaults.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return nil
        }
        return name
    }

    /// Split multi-sentence imports so each word is generated with only its own sentence.
    private static func generationUnits(sentence: String, words: [String]) -> [OCRImportUnit] {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueWords = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
        guard !trimmedSentence.isEmpty, !uniqueWords.isEmpty else { return [] }

        let extracted = OCRContextExtractor.importUnits(
            fullText: trimmedSentence,
            highlightedWords: uniqueWords
        )
        if extracted.isEmpty {
            return [OCRImportUnit(sentence: trimmedSentence, words: uniqueWords)]
        }

        let covered = Set(extracted.flatMap(\.words).map { $0.lowercased() })
        let missing = uniqueWords.filter { !covered.contains($0.lowercased()) }
        guard !missing.isEmpty else { return extracted }

        var units = extracted
        units[0].words.append(contentsOf: missing)
        return units
    }

    private static func generateForSingleContext(
        sentence: String,
        words: [String],
        sourceHint: String?,
        deckName: String?
    ) async throws -> [GeneratedCardDraft] {
        let content = try await requestCards(
            sentence: sentence,
            words: words,
            sourceHint: sourceHint,
            deckName: deckName
        )
        return try parseCards(from: content, sentence: sentence)
    }

    private static func requestCards(
        sentence: String,
        words: [String],
        sourceHint: String?,
        deckName: String?
    ) async throws -> String {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APISettings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        applyProviderHeaders(to: &request)

        let wordsList = words.joined(separator: ", ")
        let systemPrompt = """
        你是多语言词汇学习助手。用户会给你一句任意语言的原文，以及其中的生词或短语，请结合语境生成复习卡片。
        必须只返回 JSON，不要 markdown，不要额外说明。
        JSON 格式：
        {
          "source": "出处（书名/文章/作者等；不确定则空字符串）",
          "cards": [
            {
              "word": "生词",
              "phonetic": "音标（英文必须给 IPA，用 /.../ 包裹；其它语言给读法；实在没有才空字符串）",
              "type": "cloze 或 definition",
              "front": "卡片正面",
              "back": "释义及解释（词性 + 结合语境的中文释义）",
              "context_note": "整句中文翻译（目标词短译必须用【】标出）",
              "highlight": "目标词在译文中的短译（须能在 context_note 中原样找到）"
            }
          ]
        }
        规则：
        1. 每个生词生成 2 张卡：一张 cloze，一张 definition
        2. cloze 的 front：完整原句，仅把目标词/短语替换为 ______（保持原文语言）
        3. definition 的 front：必须是完整原句且保留目标词，禁止只写单词，禁止写成「xxx 是什么意思」之类提问
        4. back：只写释义及解释（注明词性，结合该句语境；不要只给脱离语境的词典义）；不要把整句翻译写进 back
        5. context_note（硬性）：必须是完整一句中文翻译。目标词对应译法必须用全角【】标出，且只标一处；【】内通常 1–6 个汉字的短译，禁止标整句或整段结果状语。正确例：政府试图【缓解】其影响。/ 他【离开时】带着苦笑。错误例：未使用【】、用 []/**/「」、或【离开时不仅好笑还更聪明】这种过长标注
        6. highlight（硬性）：填写与【】内相同的短译纯文本（不要带括号）；必须是 context_note 去掉【】后仍能原样找到的子串
        7. phonetic：每个 card 都必须填写；拉丁字母词用 IPA（例 /ˈtren.tʃənt/），日语用假名/罗马音，其它语言给常用注音；禁止把音标写进 back/front
        8. 原文是什么语言，front 中的句子就保持什么语言，不要擅自翻译原句
        9. source：若能从原文、页面提示、词库名称或公认名句较有把握地判断出处（书名、篇章名、作者），填写简洁标注，如「Poor Charlie's Almanack · Charles T. Munger」；无把握必须返回空字符串，禁止编造
        10. 若提供了词库名称：把它当作主题/书名/学习范围线索，优先按该语境理解生词与【】译法；词库名 alone 不足以确定出处时不要编造 source
        """

        var userPrompt = """
        原文：\(sentence)
        生词：\(wordsList)
        """
        if let deckName, !deckName.isEmpty {
            userPrompt += "\n词库名称（可能是书名、专题或学习范围；请作为释义语境与出处线索）：\(deckName)"
        }
        if let sourceHint, !sourceHint.isEmpty {
            userPrompt += "\n页面提示（可能含书名/标题/作者，供判断出处）：\(sourceHint)"
        }

        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw KimiCardGeneratorError.invalidResponse
        }

        if http.statusCode != 200 {
            let message = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw KimiCardGeneratorError.apiError(message)
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

        return content
    }

    static func testConnection(apiKey: String, model: String) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw KimiCardGeneratorError.missingAPIKey
        }

        guard let url = URL(string: APISettings.modelsURL) else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        applyProviderHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KimiCardGeneratorError.invalidResponse
        }

        if http.statusCode != 200 {
            let message = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw KimiCardGeneratorError.apiError(message)
        }

        _ = model
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

    private static func parseCards(from content: String, sentence: String) throws -> [GeneratedCardDraft] {
        let jsonString = extractJSON(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw KimiCardGeneratorError.parseError("无法读取 JSON 文本")
        }

        let response = try JSONDecoder().decode(KimiCardsResponse.self, from: data)
        let source = response.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        var drafts = response.cards.compactMap { item -> GeneratedCardDraft? in
            guard let type = CardType(rawValue: item.type.lowercased()) else { return nil }
            let word = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = item.back.trimmingCharacters(in: .whitespacesAndNewlines)
            let contextNote = CardContentFormatter.ensureTranslationHighlight(
                contextNote: item.contextNote,
                sense: back,
                explicitHighlight: item.highlight
            )
            return GeneratedCardDraft(
                word: word,
                phonetic: normalizedPhonetic(item.phonetic),
                sentence: sentence,
                cardType: type,
                front: CardContentFormatter.normalizedFront(
                    front: item.front,
                    sentence: sentence,
                    word: word,
                    cardType: type
                ),
                back: back,
                contextNote: contextNote,
                sourceAttribution: source
            )
        }

        guard !drafts.isEmpty else {
            throw KimiCardGeneratorError.parseError("未生成任何卡片")
        }

        // Cloze/definition pair: copy phonetic if one sibling omitted it.
        var phoneticByWord: [String: String] = [:]
        for draft in drafts {
            if let phonetic = draft.phonetic, !phonetic.isEmpty {
                phoneticByWord[draft.word.lowercased()] = phonetic
            }
        }
        for index in drafts.indices {
            if drafts[index].phonetic == nil,
               let shared = phoneticByWord[drafts[index].word.lowercased()] {
                drafts[index].phonetic = shared
            }
        }

        return drafts
    }

    private static func normalizedPhonetic(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        // Strip accidental wrappers like "IPA: ..."
        if let colon = value.firstIndex(of: ":"),
           value[..<colon].lowercased().contains("ipa") {
            value = String(value[value.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.nilIfEmpty
    }

    private static func extractJSON(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }

        if let start = trimmed.range(of: "```json"),
           let end = trimmed.range(of: "```", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return String(data: data, encoding: .utf8)
        }
        return message
    }
}

private struct KimiCardsResponse: Decodable {
    let source: String?
    let cards: [KimiCardItem]
}

private struct KimiCardItem: Decodable {
    let word: String
    let phonetic: String?
    let type: String
    let front: String
    let back: String
    let contextNote: String?
    let highlight: String?

    enum CodingKeys: String, CodingKey {
        case word, phonetic, type, front, back, highlight
        case contextNote = "context_note"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
