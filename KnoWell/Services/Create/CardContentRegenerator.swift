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
        let quote = Preprocess.fromQuote(reflection.sentence)
        guard !quote.isEmpty else {
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

    /// One appreciation card per quote (图+句 / 原文多句).
    static func generate(
        quotes: [String],
        source: String?,
        revisionHint: String? = nil,
        allowFallback: Bool = false
    ) async throws -> [GeneratedCardDraft] {
        let quotes = quotes.flatMap { Preprocess.quotes(from: $0) }.filter { !$0.isEmpty }
        guard !quotes.isEmpty else {
            throw LiteraryAppreciationGeneratorError.emptySentence
        }

        if quotes.count == 1 {
            let reflection = DailyReflection(
                sentence: quotes[0],
                translation: nil,
                source: source,
                occasion: nil,
                isAI: true
            )
            return [try await generate(from: reflection, revisionHint: revisionHint, allowFallback: allowFallback)]
        }

        var slots: [GeneratedCardDraft?] = Array(repeating: nil, count: quotes.count)
        var lastError: Error?

        await withTaskGroup(of: (Int, Result<GeneratedCardDraft, Error>).self) { group in
            var nextIndex = 0
            var inFlight = 0

            func enqueueAvailable() {
                while inFlight < Generate.maxConcurrentRequests, nextIndex < quotes.count {
                    let index = nextIndex
                    let quote = quotes[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        let reflection = DailyReflection(
                            sentence: quote,
                            translation: nil,
                            source: source,
                            occasion: nil,
                            isAI: true
                        )
                        do {
                            let draft = try await generate(
                                from: reflection,
                                revisionHint: revisionHint,
                                allowFallback: allowFallback
                            )
                            return (index, .success(draft))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }
            }

            enqueueAvailable()
            for await item in group {
                inFlight -= 1
                switch item.1 {
                case .success(let draft):
                    slots[item.0] = draft
                case .failure(let error):
                    lastError = error
                }
                enqueueAvailable()
            }
        }

        let drafts = slots.compactMap { $0 }
        if drafts.isEmpty {
            throw lastError ?? LiteraryAppreciationGeneratorError.emptyAppreciation
        }
        return drafts
    }

    private static func fetchAppreciation(
        from reflection: DailyReflection,
        revisionHint: String?,
        allowFallback: Bool
    ) async throws -> GeneratedCardDraft {
        guard APISettings.canUseAI else {
            throw LiteraryAppreciationGeneratorError.missingAPIKey
        }

        let sentence = Preprocess.fromQuote(reflection.sentence)
        let translation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        do {
            let payload = try await Generate.appreciation(
                sentence: sentence,
                using: OpenAIGenerateTransport(timeout: requestTimeout),
                source: source,
                translation: translation,
                occasion: occasion,
                revisionHint: revisionHint
            )
            return try makeDraft(
                from: payload,
                reflection: reflection,
                allowFallback: allowFallback
            )
        } catch {
            throw mapAppreciationError(error)
        }
    }

    private static func mapAppreciationError(_ error: Error) -> Error {
        if let generate = error as? GenerateError {
            switch generate {
            case .emptyInput:
                return LiteraryAppreciationGeneratorError.emptySentence
            case .parseFailed:
                return LiteraryAppreciationGeneratorError.parseError(L10n.generateFormatErrorDetail)
            }
        }
        if let existing = error as? LiteraryAppreciationGeneratorError {
            return existing
        }
        if let generator = error as? CardGeneratorError {
            switch generator {
            case .missingAPIKey: return LiteraryAppreciationGeneratorError.missingAPIKey
            case .invalidResponse: return LiteraryAppreciationGeneratorError.invalidResponse
            case .apiError(let message): return LiteraryAppreciationGeneratorError.apiError(message)
            case .parseError(let message): return LiteraryAppreciationGeneratorError.parseError(message)
            case .timedOut: return LiteraryAppreciationGeneratorError.invalidResponse
            case .allDuplicates, .quotaInsufficient: return generator
            }
        }
        return error
    }

    private static func makeDraft(
        from payload: AppreciationPayload,
        reflection: DailyReflection,
        allowFallback: Bool
    ) throws -> GeneratedCardDraft {
        let sentence = reflection.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let providedTranslation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let translation = payload.translation ?? providedTranslation
        let appreciation = payload.mergedAppreciation ?? ""

        let title = payload.title
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
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
