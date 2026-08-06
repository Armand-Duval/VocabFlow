import Foundation

enum LiteraryAppreciationGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError(String)
    case emptySentence

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
        case .emptySentence:
            L10n.reviewDailyCollectNeedSentence
        }
    }
}

enum LiteraryAppreciationGenerator {
    private static let requestTimeout: TimeInterval = 45

    static func generate(from reflection: DailyReflection) async throws -> GeneratedCardDraft {
        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            throw LiteraryAppreciationGeneratorError.emptySentence
        }

        if APISettings.canUseAI {
            do {
                return try await fetchAppreciation(from: reflection)
            } catch {
                return fallbackDraft(from: reflection)
            }
        }
        return fallbackDraft(from: reflection)
    }

    private static func fetchAppreciation(from reflection: DailyReflection) async throws -> GeneratedCardDraft {
        guard APISettings.canUseAI else {
            throw LiteraryAppreciationGeneratorError.missingAPIKey
        }

        let content = try await requestAppreciation(from: reflection)
        return try parseAppreciation(from: content, reflection: reflection)
    }

    private static func requestAppreciation(from reflection: DailyReflection) async throws -> String {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw LiteraryAppreciationGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APISettings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let systemPrompt = """
        你是克制的文学赏析助手，为学习 App「致知」把名篇名句整理成「赏析卡」。
        只返回 JSON，不要 markdown，不要代码块，不要字段外说明。

        格式：
        {
          "title": "一句主题（8–18 字，点出情感或哲理）",
          "translation": "中文译文；原文已是现代汉语则空字符串",
          "appreciation": "赏析正文（中文 2–4 短段，共 120–280 字）：意象/情感/背景/语言特点，可分段用换行",
          "takeaway": "可选：若只能记住一个画面或感受（1 句；没有则空字符串）"
        }

        规则：
        1. 禁止拆生词、禁止出挖空、禁止词表与同义词罗列
        2. 不要复述整句翻译当作赏析；要解释「好在哪里」
        3. 无把握的背景不要编造；不确定则略过
        4. 若用户已提供译文，translation 可沿用或轻微润色，不要改成另一句话
        5. appreciation 宜短、可读，像写给爱读者的随笔
        """

        var userPrompt = """
        原文：
        \(sentence)
        """
        if !source.isEmpty {
            userPrompt += "\n出处：\(source)"
        }
        if !translation.isEmpty {
            userPrompt += "\n已有译文（可沿用）：\(translation)"
        }
        if !occasion.isEmpty {
            userPrompt += "\n缘由：\(occasion)"
        }

        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": APISettings.chatTemperature(preferred: 0.55),
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LiteraryAppreciationGeneratorError.invalidResponse
        }
        if http.statusCode != 200 {
            let message = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw LiteraryAppreciationGeneratorError.apiError(message)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LiteraryAppreciationGeneratorError.invalidResponse
        }
        return content
    }

    private static func parseAppreciation(
        from content: String,
        reflection: DailyReflection
    ) throws -> GeneratedCardDraft {
        let jsonString = extractJSON(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw LiteraryAppreciationGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        let payload: AppreciationResponse
        do {
            payload = try JSONDecoder().decode(AppreciationResponse.self, from: data)
        } catch {
            throw LiteraryAppreciationGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let providedTranslation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let aiTranslation = payload.translation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let translation = aiTranslation ?? providedTranslation

        var appreciation = payload.appreciation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        if let takeaway = payload.takeaway?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            appreciation = appreciation.isEmpty ? takeaway : "\(appreciation)\n\n\(takeaway)"
        }

        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? L10n.cardTypeAppreciation

        if appreciation.isEmpty {
            return fallbackDraft(from: reflection, title: title, translation: translation)
        }

        return GeneratedCardDraft(
            word: CardContentFormatter.appreciationWordLabel(source: source, sentence: sentence),
            sentence: sentence,
            cardType: .appreciation,
            front: sentence,
            back: title,
            contextNote: translation,
            usageNote: appreciation,
            sourceAttribution: source,
            isSelected: true,
            isRecommended: true
        )
    }

    static func fallbackDraft(
        from reflection: DailyReflection,
        title: String? = nil,
        translation: String? = nil
    ) -> GeneratedCardDraft {
        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let resolvedTranslation = translation
            ?? reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let resolvedTitle = title
            ?? reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? L10n.cardTypeAppreciation

        var appreciationParts: [String] = []
        if let resolvedTranslation, !resolvedTranslation.isEmpty {
            appreciationParts.append(resolvedTranslation)
        }
        if let source, !source.isEmpty {
            appreciationParts.append(L10n.cardSource(source))
        }

        return GeneratedCardDraft(
            word: CardContentFormatter.appreciationWordLabel(source: source, sentence: sentence),
            sentence: sentence,
            cardType: .appreciation,
            front: sentence,
            back: resolvedTitle,
            contextNote: resolvedTranslation,
            usageNote: appreciationParts.isEmpty ? nil : appreciationParts.joined(separator: "\n\n"),
            sourceAttribution: source,
            isSelected: true,
            isRecommended: true
        )
    }

    private static func extractJSON(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
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

private struct AppreciationResponse: Decodable {
    let title: String?
    let translation: String?
    let appreciation: String?
    let takeaway: String?
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
