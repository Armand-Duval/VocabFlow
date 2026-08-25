import Foundation

public struct GeneratePrompt: Equatable, Sendable {
    public var system: String
    public var user: String
    public var temperature: Double
    public var jsonObject: Bool
    public var maxTokens: Int?
    /// Cloud quota: vocabulary words in this request (usually the batch size).
    public var billedUnits: Int

    public init(
        system: String,
        user: String,
        temperature: Double,
        jsonObject: Bool = true,
        maxTokens: Int? = nil,
        billedUnits: Int = 1
    ) {
        self.system = system
        self.user = user
        self.temperature = temperature
        self.jsonObject = jsonObject
        self.maxTokens = maxTokens
        self.billedUnits = billedUnits
    }
}

public protocol GenerateTransport: Sendable {
    func complete(_ prompt: GeneratePrompt) async throws -> String
}

public struct GenerateHooks: Sendable {
    public var onProgress: (@Sendable (Int, Int) async -> Void)?
    public var onBatchStarted: (@Sendable (_ sentence: String, _ words: [String]) async -> Void)?
    public var onBatchFinished: (@Sendable (_ sentence: String, _ words: [String], _ cards: [CardStudyContent], _ error: Error?) async -> Void)?

    public init(
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil,
        onBatchStarted: (@Sendable (String, [String]) async -> Void)? = nil,
        onBatchFinished: (@Sendable (String, [String], [CardStudyContent], Error?) async -> Void)? = nil
    ) {
        self.onProgress = onProgress
        self.onBatchStarted = onBatchStarted
        self.onBatchFinished = onBatchFinished
    }
}

public enum GenerateError: Error, Equatable {
    case emptyInput
    case parseFailed
}

/// Card-generation black box. HTTP / keys / quota live in `GenerateTransport`.
public enum Generate {
    public static let maxWordsPerRequest = 3
    public static let maxConcurrentRequests = 3
    public static let vocabTemperature = 0.3
    public static let appreciationTemperature = 0.55
    public static let vocabMaxTokens = 6_000

    public static func batchCount(for units: [OCRImportUnit]) -> Int {
        units.reduce(0) { partial, unit in
            partial + unit.words.chunked(into: maxWordsPerRequest).count
        }
    }

    /// [(sentence, words)] → vocab cards.
    public static func cards(
        units: [OCRImportUnit],
        using transport: any GenerateTransport,
        sourceHint: String? = nil,
        deckName: String? = nil,
        requiredCardType: CardType? = nil,
        imageOnlySource: Bool = false,
        revisionHint: String? = nil,
        hooks: GenerateHooks = GenerateHooks()
    ) async throws -> [CardStudyContent] {
        guard !units.isEmpty else { throw GenerateError.emptyInput }

        var jobs: [(sentence: String, words: [String])] = []
        for unit in units {
            for batch in unit.words.chunked(into: maxWordsPerRequest) {
                jobs.append((unit.sentence, batch))
            }
        }
        guard !jobs.isEmpty else { throw GenerateError.emptyInput }

        let total = jobs.count
        await hooks.onProgress?(0, total)

        var allCards: [CardStudyContent] = []
        var lastError: Error?
        var completed = 0

        await withTaskGroup(of: (sentence: String, words: [String], result: Result<[CardStudyContent], Error>).self) { group in
            var nextIndex = 0
            var inFlight = 0

            func enqueueAvailable() {
                while inFlight < maxConcurrentRequests, nextIndex < jobs.count {
                    let job = jobs[nextIndex]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        do {
                            await hooks.onBatchStarted?(job.sentence, job.words)
                            let cards = try await completeVocabBatch(
                                sentence: job.sentence,
                                words: job.words,
                                using: transport,
                                sourceHint: sourceHint,
                                deckName: deckName,
                                requiredCardType: requiredCardType,
                                imageOnlySource: imageOnlySource,
                                revisionHint: revisionHint
                            )
                            return (job.sentence, job.words, .success(cards))
                        } catch {
                            return (job.sentence, job.words, .failure(error))
                        }
                    }
                }
            }

            enqueueAvailable()

            for await item in group {
                inFlight -= 1
                switch item.result {
                case .success(let cards):
                    allCards.append(contentsOf: cards)
                    await hooks.onBatchFinished?(item.sentence, item.words, cards, nil)
                case .failure(let error):
                    lastError = error
                    await hooks.onBatchFinished?(item.sentence, item.words, [], error)
                }
                completed += 1
                await hooks.onProgress?(completed, total)
                enqueueAvailable()
            }
        }

        if !allCards.isEmpty {
            return allCards
        }
        throw lastError ?? GenerateError.parseFailed
    }

    /// Quote → appreciation payload (app maps to a card).
    public static func appreciation(
        sentence: String,
        using transport: any GenerateTransport,
        source: String = "",
        translation: String = "",
        occasion: String = "",
        revisionHint: String? = nil
    ) async throws -> AppreciationPayload {
        let quote = Preprocess.fromQuote(sentence)
        guard !quote.isEmpty else { throw GenerateError.emptyInput }
        return try await completeOneQuote(
            quote: quote,
            using: transport,
            source: source,
            translation: translation,
            occasion: occasion,
            revisionHint: revisionHint
        )
    }

    /// Quotes → appreciation payloads (one card each). Does not re-split; call `Preprocess.quotes` first.
    public static func appreciation(
        sentences: [String],
        using transport: any GenerateTransport,
        source: String = "",
        translation: String = "",
        occasion: String = "",
        revisionHint: String? = nil
    ) async throws -> [AppreciationPayload] {
        let quotes = sentences.map(Preprocess.fromQuote).filter { !$0.isEmpty }
        guard !quotes.isEmpty else { throw GenerateError.emptyInput }
        if quotes.count == 1 {
            return [try await completeOneQuote(
                quote: quotes[0],
                using: transport,
                source: source,
                translation: translation,
                occasion: occasion,
                revisionHint: revisionHint
            )]
        }

        var slots: [AppreciationPayload?] = Array(repeating: nil, count: quotes.count)
        var lastError: Error?

        await withTaskGroup(of: (Int, Result<AppreciationPayload, Error>).self) { group in
            var nextIndex = 0
            var inFlight = 0

            func enqueueAvailable() {
                while inFlight < maxConcurrentRequests, nextIndex < quotes.count {
                    let index = nextIndex
                    let quote = quotes[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        do {
                            let payload = try await completeOneQuote(
                                quote: quote,
                                using: transport,
                                source: source,
                                translation: translation,
                                occasion: occasion,
                                revisionHint: revisionHint
                            )
                            return (index, .success(payload))
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
                case .success(let payload):
                    slots[item.0] = payload
                case .failure(let error):
                    lastError = error
                }
                enqueueAvailable()
            }
        }

        let payloads = slots.compactMap { $0 }
        if payloads.isEmpty {
            throw lastError ?? GenerateError.parseFailed
        }
        return payloads
    }

    private static func completeOneQuote(
        quote: String,
        using transport: any GenerateTransport,
        source: String,
        translation: String,
        occasion: String,
        revisionHint: String?
    ) async throws -> AppreciationPayload {
        let prompt = GeneratePrompt(
            system: AppreciationPrompt.system,
            user: AppreciationPrompt.user(
                sentence: quote,
                source: source,
                translation: translation,
                occasion: occasion,
                revisionHint: revisionHint
            ),
            temperature: appreciationTemperature,
            billedUnits: 1
        )
        let content = try await transport.complete(prompt)
        do {
            return try AppreciationParser.parse(from: content)
        } catch {
            throw GenerateError.parseFailed
        }
    }

    private static func completeVocabBatch(
        sentence: String,
        words: [String],
        using transport: any GenerateTransport,
        sourceHint: String?,
        deckName: String?,
        requiredCardType: CardType?,
        imageOnlySource: Bool,
        revisionHint: String?
    ) async throws -> [CardStudyContent] {
        let prompt = GeneratePrompt(
            system: CardGenerationPrompt.system(requiredCardType: requiredCardType),
            user: CardGenerationPrompt.user(
                sentence: sentence,
                words: words,
                deckName: deckName,
                sourceHint: sourceHint,
                imageOnlySource: imageOnlySource,
                revisionHint: revisionHint
            ),
            temperature: vocabTemperature,
            maxTokens: vocabMaxTokens,
            billedUnits: max(words.count, 1)
        )

        var lastError: Error = GenerateError.parseFailed
        for attempt in 1...2 {
            do {
                let content = try await transport.complete(prompt)
                return try CardGenerationParser.parse(
                    from: content,
                    sentence: sentence,
                    requiredCardType: requiredCardType
                )
            } catch {
                lastError = mapParse(error)
                if attempt == 2 { throw lastError }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        throw lastError
    }

    private static func mapParse(_ error: Error) -> Error {
        if error is CardGenerationParseError {
            return GenerateError.parseFailed
        }
        return error
    }
}

fileprivate extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
