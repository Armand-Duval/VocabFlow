import Foundation

enum CardContentRegeneratorError: LocalizedError {
    case noMatchingDraft

    var errorDescription: String? {
        switch self {
        case .noMatchingDraft:
            L10n.cardRegenerateNoMatch
        }
    }
}

/// Preview triage: replace a draft before it is saved.
enum CardDraftRegenerator {
    @MainActor
    static func replace(
        _ draft: GeneratedCardDraft,
        reason: CardReplaceReason,
        deckName: String?
    ) async throws -> GeneratedCardDraft {
        if draft.cardType == .appreciation {
            let reflection = DailyReflection(
                sentence: draft.sentence,
                translation: draft.contextNote,
                source: draft.sourceAttribution,
                occasion: draft.back,
                isAI: true
            )
            var next = try await LiteraryAppreciationGenerator.generate(
                from: reflection,
                revisionHint: reason.promptInstruction,
                allowFallback: false
            )
            next.sourceImagePath = draft.sourceImagePath
            next.isSelected = true
            next.isRecommended = true
            return next
        }
        return try await CardGenerator.regenerate(
            draft: draft,
            reason: reason,
            deckName: deckName
        )
    }
}

/// Single-card AI regenerate using the same generator rules as new cards / bulk migrate.
enum CardContentRegenerator {
    @MainActor
    static func regenerate(_ card: FlashCard) async throws {
        let sentence = card.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !word.isEmpty else {
            throw CardContentRegeneratorError.noMatchingDraft
        }

        if card.cardType == .appreciation {
            let reflection = DailyReflection(
                sentence: sentence,
                translation: card.contextNote,
                source: card.sourceAttribution,
                occasion: CardContentFormatter.senseText(card.back),
                isAI: true
            )
            let draft = try await LiteraryAppreciationGenerator.generate(from: reflection, allowFallback: false)
            CardContentSync.applyGeneratedContent(draft, to: card)
            DeckCardCountService.notifyCatalogChanged()
            return
        }

        let drafts = try await CardGenerator.generate(
            sentence: sentence,
            words: [word],
            sourceHint: card.sourceAttribution,
            deckName: card.deck?.name,
            requiredCardType: card.cardType
        )
        guard let draft = matchingDraft(in: drafts, word: word, cardType: card.cardType) else {
            throw CardContentRegeneratorError.noMatchingDraft
        }

        CardContentSync.applyGeneratedContent(draft, to: card)
        DeckCardCountService.notifyCatalogChanged()
    }

    /// Prefer same word + card type; fall back to same word so cloze/definition siblings still update.
    static func matchingDraft(
        in drafts: [GeneratedCardDraft],
        word: String,
        cardType: CardType
    ) -> GeneratedCardDraft? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = drafts.first {
            $0.cardType == cardType
                && $0.word.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if let typed { return typed }
        return drafts.first { $0.word.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

// MARK: - Literary appreciation cards

enum LiteraryAppreciationGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError(String)
    case emptySentence
    case emptyAppreciation

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
        case .emptyAppreciation:
            L10n.generateEmptyAppreciationError
        }
    }
}

enum LiteraryAppreciationGenerator {
    private static let requestTimeout: TimeInterval = 45

    static func generate(
        from reflection: DailyReflection,
        revisionHint: String? = nil,
        allowFallback: Bool = true
    ) async throws -> GeneratedCardDraft {
        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            throw LiteraryAppreciationGeneratorError.emptySentence
        }

        if APISettings.canUseAI {
            do {
                return try await fetchAppreciation(
                    from: reflection,
                    revisionHint: revisionHint,
                    allowFallback: allowFallback
                )
            } catch {
                if CloudAIQuota.isExhausted(error) { throw error }
                if let draft = usableFallback(from: reflection, allowed: allowFallback) {
                    return draft
                }
                throw error
            }
        }
        if let draft = usableFallback(from: reflection, allowed: allowFallback) {
            return draft
        }
        throw LiteraryAppreciationGeneratorError.emptyAppreciation
    }

    private static func fetchAppreciation(
        from reflection: DailyReflection,
        revisionHint: String?,
        allowFallback: Bool
    ) async throws -> GeneratedCardDraft {
        guard APISettings.canUseAI else {
            throw LiteraryAppreciationGeneratorError.missingAPIKey
        }

        let content = try await requestAppreciation(from: reflection, revisionHint: revisionHint)
        return try parseAppreciation(from: content, reflection: reflection, allowFallback: allowFallback)
    }

    private static func requestAppreciation(
        from reflection: DailyReflection,
        revisionHint: String?
    ) async throws -> String {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw LiteraryAppreciationGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        APISettings.applyChatHeaders(to: &request)

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
        if let revisionHint, !revisionHint.isEmpty {
            userPrompt += "\n重做要求：\(revisionHint)\n请换一个切入角度，不要重复上一版赏析。"
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
        CloudAIQuota.ingest(http: http, data: data)
        if http.statusCode != 200 {
            let raw = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            let message = CloudAIQuota.mappedMessage(statusCode: http.statusCode, raw: raw) ?? raw
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
        reflection: DailyReflection,
        allowFallback: Bool
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
            if let draft = usableFallback(
                from: reflection,
                allowed: allowFallback,
                title: title,
                translation: translation
            ) {
                return draft
            }
            throw LiteraryAppreciationGeneratorError.emptyAppreciation
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

    private static func usableFallback(
        from reflection: DailyReflection,
        allowed: Bool,
        title: String? = nil,
        translation: String? = nil
    ) -> GeneratedCardDraft? {
        guard allowed else { return nil }
        let draft = fallbackDraft(from: reflection, title: title, translation: translation)
        return CardContentFormatter.isHollowAppreciation(draft) ? nil : draft
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let message = json["error"] as? String { return message }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)
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
