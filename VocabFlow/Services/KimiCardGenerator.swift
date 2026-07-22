import Foundation

enum KimiCardGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先在「设置」中填写 Kimi API Key，或配置内置默认 Key。"
        case .invalidResponse:
            "Kimi 返回了无效响应。"
        case .apiError(let message):
            message
        case .parseError(let message):
            "解析卡片失败：\(message)"
        }
    }
}

enum KimiCardGenerator {
    static func generate(sentence: String, words: [String]) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseKimi else {
            throw KimiCardGeneratorError.missingAPIKey
        }

        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueWords = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        guard !trimmedSentence.isEmpty, !uniqueWords.isEmpty else {
            return []
        }

        let content = try await requestCards(sentence: trimmedSentence, words: uniqueWords)
        return try parseCards(from: content, sentence: trimmedSentence)
    }

    private static func requestCards(sentence: String, words: [String]) async throws -> String {
        guard let url = URL(string: "\(APISettings.baseURL)/chat/completions") else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APISettings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let wordsList = words.joined(separator: ", ")
        let systemPrompt = """
        你是多语言词汇学习助手。用户会给你一句任意语言的原文，以及其中的生词或短语，请结合语境生成复习卡片。
        必须只返回 JSON，不要 markdown，不要额外说明。
        JSON 格式：
        {
          "cards": [
            {
              "word": "生词",
              "type": "cloze 或 definition",
              "front": "卡片正面",
              "back": "卡片背面（含释义、词性、音标/读法、语境说明）",
              "context_note": ""
            }
          ]
        }
        规则：
        1. 每个生词生成 2 张卡：一张 cloze（在原句中把该词替换为 ______，保持原文语言），一张 definition（问该词/短语在此句中的意思）
        2. 释义必须结合原句语境，不要只给词典通用释义
        3. 所有中文解释和语境说明都写在 back 里；back 用中文解释；如有音标/罗马音/读法可附上；注明词性
        4. 原文是什么语言，front 中的句子就保持什么语言，不要擅自翻译原句
        5. context_note 留空字符串，不要把语境说明单独输出
        """

        let userPrompt = """
        原文：\(sentence)
        生词：\(wordsList)
        """

        let body: [String: Any] = [
            "model": APISettings.kimiModel,
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

    private static func parseCards(from content: String, sentence: String) throws -> [GeneratedCardDraft] {
        let jsonString = extractJSON(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw KimiCardGeneratorError.parseError("无法读取 JSON 文本")
        }

        let response = try JSONDecoder().decode(KimiCardsResponse.self, from: data)
        let drafts = response.cards.compactMap { item -> GeneratedCardDraft? in
            guard let type = CardType(rawValue: item.type.lowercased()) else { return nil }
            return GeneratedCardDraft(
                word: item.word,
                sentence: sentence,
                cardType: type,
                front: item.front,
                back: CardContentFormatter.mergedBack(back: item.back, contextNote: item.contextNote),
                contextNote: nil
            )
        }

        guard !drafts.isEmpty else {
            throw KimiCardGeneratorError.parseError("未生成任何卡片")
        }

        return drafts
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
    let cards: [KimiCardItem]
}

private struct KimiCardItem: Decodable {
    let word: String
    let type: String
    let front: String
    let back: String
    let contextNote: String?

    enum CodingKeys: String, CodingKey {
        case word, type, front, back
        case contextNote = "context_note"
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
