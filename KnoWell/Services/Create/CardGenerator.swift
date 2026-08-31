import Foundation

enum CardGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError(String)
    case timedOut
    /// All requested words already exist in the target deck for this sentence.
    case allDuplicates
    /// Cloud free quota is counted per vocabulary word, not per HTTP batch.
    case quotaInsufficient(needed: Int, remaining: Int)

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
        case .timedOut:
            L10n.generateTimeoutError
        case .allDuplicates:
            L10n.createGenerateAllDuplicates
        case .quotaInsufficient(let needed, let remaining):
            L10n.cloudQuotaInsufficient(needed, remaining)
        }
    }
}

enum CardGenerator {
    private static let requestTimeout: TimeInterval = 90

    /// Split multi-sentence imports so each word is generated with only its own sentence.
    static func makeGenerationUnits(sentence: String, words: [String]) -> [OCRImportUnit] {
        Preprocess.fromText(sentence: sentence, words: words)
    }

    /// Prepare units + batch count after optional deck-scoped dedupe (unit sentence keys).
    static func prepareGeneration(
        sentence: String,
        words: [String],
        skipExistingInDeckID: UUID? = nil,
        imageOnlySource: Bool = false
    ) throws -> (units: [OCRImportUnit], skippedCount: Int, batchCount: Int) {
        let units = Preprocess.fromText(
            sentence: sentence,
            words: words,
            imageOnlySource: imageOnlySource
        )
        let prepared: (units: [OCRImportUnit], skippedCount: Int)
        if let deckID = skipExistingInDeckID {
            prepared = SharedDedupeIndex.filterNewUnits(units, deckID: deckID)
            guard !prepared.units.isEmpty else {
                throw CardGeneratorError.allDuplicates
            }
        } else {
            prepared = (units, 0)
        }

        return (prepared.units, prepared.skippedCount, Generate.batchCount(for: prepared.units))
    }

    /// - Parameter skipExistingInDeckID: When set, drop word+sentence pairs already in that deck
    ///   before calling the model. Use for **new** cards only — regenerators must leave this `nil`.
    /// - Parameter requiredCardType: When set, each word yields only that card type (for regenerate).
    /// - Parameter onProgress: Invoked on the main actor as each batch finishes `(completed, total)`.
    /// - Parameter onBatchStarted: Per-batch words that just began an upstream request.
    /// - Parameter onBatchFinished: Per-batch word outcomes for queue / progress UIs.
    static func generate(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        deckName: String? = nil,
        requiredCardType: CardType? = nil,
        skipExistingInDeckID: UUID? = nil,
        imageOnlySource: Bool = false,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil,
        onBatchStarted: (@MainActor (_ sentence: String, _ words: [String]) -> Void)? = nil,
        onBatchFinished: (@MainActor (_ sentence: String, _ words: [String], _ drafts: [GeneratedCardDraft], _ error: Error?) -> Void)? = nil
    ) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseAI else {
            throw CardGeneratorError.missingAPIKey
        }

        let prepared = try prepareGeneration(
            sentence: sentence,
            words: words,
            skipExistingInDeckID: skipExistingInDeckID,
            imageOnlySource: imageOnlySource
        )
        return try await generate(
            units: prepared.units,
            sourceHint: sourceHint,
            deckName: deckName,
            requiredCardType: requiredCardType,
            imageOnlySource: imageOnlySource,
            onProgress: onProgress,
            onBatchStarted: onBatchStarted,
            onBatchFinished: onBatchFinished
        )
    }

    static func generate(
        units: [OCRImportUnit],
        sourceHint: String? = nil,
        deckName: String? = nil,
        requiredCardType: CardType? = nil,
        imageOnlySource: Bool = false,
        revisionHint: String? = nil,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil,
        onBatchStarted: (@MainActor (_ sentence: String, _ words: [String]) -> Void)? = nil,
        onBatchFinished: (@MainActor (_ sentence: String, _ words: [String], _ drafts: [GeneratedCardDraft], _ error: Error?) -> Void)? = nil
    ) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseAI else {
            throw CardGeneratorError.missingAPIKey
        }
        guard !units.isEmpty else { return [] }

        let hint = sourceHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let deck = usefulDeckName(deckName)
        let expandSiblings = requiredCardType == nil
        let transport = OpenAIGenerateTransport(timeout: requestTimeout)

        do {
            let studies = try await Generate.cards(
                units: units,
                using: transport,
                sourceHint: hint,
                deckName: deck,
                requiredCardType: requiredCardType,
                imageOnlySource: imageOnlySource,
                revisionHint: revisionHint,
                hooks: GenerateHooks(
                    onProgress: { completed, total in
                        await MainActor.run { onProgress?(completed, total) }
                    },
                    onBatchStarted: { sentence, words in
                        await MainActor.run { onBatchStarted?(sentence, words) }
                    },
                    onBatchFinished: { sentence, words, cards, error in
                        await MainActor.run {
                            let drafts = error == nil
                                ? mapDrafts(cards, expandSiblings: expandSiblings)
                                : []
                            onBatchFinished?(sentence, words, drafts, error.map(mapGenerateError))
                        }
                    }
                )
            )
            return mapDrafts(studies, expandSiblings: expandSiblings)
        } catch {
            throw mapGenerateError(error)
        }
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

    /// Replace one preview draft using the user's keep/drop reason.
    static func regenerate(
        draft: GeneratedCardDraft,
        reason: CardReplaceReason,
        deckName: String? = nil
    ) async throws -> GeneratedCardDraft {
        guard APISettings.canUseAI else {
            throw CardGeneratorError.missingAPIKey
        }
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !sentence.isEmpty else {
            throw CardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        let drafts = try await generate(
            units: [OCRImportUnit(sentence: sentence, words: [word])],
            sourceHint: draft.sourceAttribution,
            deckName: usefulDeckName(deckName),
            requiredCardType: draft.cardType,
            revisionHint: reason.promptInstruction
        )
        guard var next = drafts.first(where: {
            $0.cardType == draft.cardType
                && $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) ?? drafts.first(where: {
            $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) else {
            throw CardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
        next.sourceImagePath = draft.sourceImagePath
        next.isSelected = true
        next.isRecommended = true
        return next
    }

    static func testConnection(apiKey: String, model: String) async throws {
        if APISettings.usesCloudProxy {
            guard let url = URL(string: KnoWellCloud.healthURL) else {
                throw CardGeneratorError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let message = OpenAIChatContent.errorMessage(from: data) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                throw CardGeneratorError.apiError(message)
            }
            _ = model
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CardGeneratorError.missingAPIKey
        }

        guard let url = URL(string: APISettings.modelsURL) else {
            throw CardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        APISettings.applyChatHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CardGeneratorError.invalidResponse
        }

        if http.statusCode != 200 {
            let message = OpenAIChatContent.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw CardGeneratorError.apiError(message)
        }

        _ = model
    }

    private static func mapDrafts(
        _ studies: [CardStudyContent],
        expandSiblings: Bool
    ) -> [GeneratedCardDraft] {
        var drafts = studies.map { GeneratedCardDraft(from: $0) }
        if expandSiblings {
            drafts = CardContentFormatter.expandOptionalSiblings(drafts)
        }
        return drafts
    }

    private static func mapGenerateError(_ error: Error) -> Error {
        if let generate = error as? GenerateError {
            switch generate {
            case .emptyInput, .parseFailed:
                return CardGeneratorError.parseError(L10n.generateFormatErrorDetail)
            }
        }
        if let generatorError = error as? CardGeneratorError {
            return generatorError
        }
        if let url = error as? URLError, url.code == .timedOut {
            return CardGeneratorError.timedOut
        }
        if error is DecodingError {
            return CardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
        return error
    }
}

struct OpenAIGenerateTransport: GenerateTransport {
    var timeout: TimeInterval

    func complete(_ prompt: GeneratePrompt) async throws -> String {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw CardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        APISettings.applyChatHeaders(to: &request)
        if APISettings.usesCloudProxy {
            request.setValue(String(max(prompt.billedUnits, 1)), forHTTPHeaderField: "X-KnoWell-Units")
        }

        var body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user]
            ],
            "temperature": APISettings.chatTemperature(preferred: prompt.temperature)
        ]
        if prompt.jsonObject {
            body["response_format"] = ["type": "json_object"]
        }
        if let maxTokens = prompt.maxTokens {
            body["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CardGeneratorError.invalidResponse
        }
        CloudAIQuota.ingest(http: http, data: data)

        if http.statusCode != 200 {
            let raw = OpenAIChatContent.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            let message = CloudAIQuota.mappedMessage(statusCode: http.statusCode, raw: raw) ?? raw
            throw CardGeneratorError.apiError(message)
        }

        let message: OpenAIChatContent.Message
        do {
            message = try OpenAIChatContent.parse(data)
        } catch {
            throw CardGeneratorError.invalidResponse
        }
        if message.isTruncated {
            throw CardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
        return message.text
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
