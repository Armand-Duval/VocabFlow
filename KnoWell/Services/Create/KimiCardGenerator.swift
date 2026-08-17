import Foundation

enum KimiCardGeneratorError: LocalizedError {
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

enum KimiCardGenerator {
    /// Keep each model reply small enough to finish within timeout and avoid truncated JSON.
    private static let maxWordsPerRequest = 3
    /// Cap parallel Moonshot calls — enough speedup without tripping rate limits.
    private static let maxConcurrentRequests = 3
    private static let requestTimeout: TimeInterval = 90
    private static let maxOutputTokens = 6_000

    private struct GenerationJob: Sendable {
        let sentence: String
        let words: [String]
    }

    /// Split multi-sentence imports so each word is generated with only its own sentence.
    static func makeGenerationUnits(sentence: String, words: [String]) -> [OCRImportUnit] {
        generationUnits(sentence: sentence, words: words)
    }

    /// Prepare units + batch count after optional deck-scoped dedupe (unit sentence keys).
    static func prepareGeneration(
        sentence: String,
        words: [String],
        skipExistingInDeckID: UUID? = nil
    ) throws -> (units: [OCRImportUnit], skippedCount: Int, batchCount: Int) {
        let units = generationUnits(sentence: sentence, words: words)
        let prepared: (units: [OCRImportUnit], skippedCount: Int)
        if let deckID = skipExistingInDeckID {
            prepared = SharedDedupeIndex.filterNewUnits(units, deckID: deckID)
            guard !prepared.units.isEmpty else {
                throw KimiCardGeneratorError.allDuplicates
            }
        } else {
            prepared = (units, 0)
        }

        let batchCount = prepared.units.reduce(0) { partial, unit in
            partial + unit.words.chunked(into: maxWordsPerRequest).count
        }
        return (prepared.units, prepared.skippedCount, batchCount)
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
        mode: CardGenerationMode? = nil,
        requiredCardType: CardType? = nil,
        skipExistingInDeckID: UUID? = nil,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil,
        onBatchStarted: (@MainActor (_ sentence: String, _ words: [String]) -> Void)? = nil,
        onBatchFinished: (@MainActor (_ sentence: String, _ words: [String], _ drafts: [GeneratedCardDraft], _ error: Error?) -> Void)? = nil
    ) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseAI else {
            throw KimiCardGeneratorError.missingAPIKey
        }

        let prepared = try prepareGeneration(
            sentence: sentence,
            words: words,
            skipExistingInDeckID: skipExistingInDeckID
        )
        return try await generate(
            units: prepared.units,
            sourceHint: sourceHint,
            deckName: deckName,
            mode: mode,
            requiredCardType: requiredCardType,
            onProgress: onProgress,
            onBatchStarted: onBatchStarted,
            onBatchFinished: onBatchFinished
        )
    }

    static func generate(
        units: [OCRImportUnit],
        sourceHint: String? = nil,
        deckName: String? = nil,
        mode: CardGenerationMode? = nil,
        requiredCardType: CardType? = nil,
        onProgress: (@MainActor (Int, Int) -> Void)? = nil,
        onBatchStarted: (@MainActor (_ sentence: String, _ words: [String]) -> Void)? = nil,
        onBatchFinished: (@MainActor (_ sentence: String, _ words: [String], _ drafts: [GeneratedCardDraft], _ error: Error?) -> Void)? = nil
    ) async throws -> [GeneratedCardDraft] {
        guard APISettings.canUseAI else {
            throw KimiCardGeneratorError.missingAPIKey
        }
        guard !units.isEmpty else { return [] }

        let hint = sourceHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let deck = usefulDeckName(deckName)

        var jobs: [GenerationJob] = []
        for unit in units {
            for batch in unit.words.chunked(into: maxWordsPerRequest) {
                jobs.append(GenerationJob(sentence: unit.sentence, words: batch))
            }
        }
        guard !jobs.isEmpty else { return [] }

        let total = jobs.count
        await MainActor.run { onProgress?(0, total) }

        let collected = await runJobsInParallel(
            jobs,
            sourceHint: hint,
            deckName: deck,
            mode: mode ?? CardGenerationPreferences.mode,
            requiredCardType: requiredCardType,
            onProgress: onProgress,
            onBatchStarted: onBatchStarted,
            onBatchFinished: onBatchFinished
        )

        if !collected.drafts.isEmpty {
            return collected.drafts
        }
        throw collected.lastError
            ?? KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
    }

    private static func runJobsInParallel(
        _ jobs: [GenerationJob],
        sourceHint: String?,
        deckName: String?,
        mode: CardGenerationMode,
        requiredCardType: CardType?,
        onProgress: (@MainActor (Int, Int) -> Void)?,
        onBatchStarted: (@MainActor (_ sentence: String, _ words: [String]) -> Void)?,
        onBatchFinished: (@MainActor (_ sentence: String, _ words: [String], _ drafts: [GeneratedCardDraft], _ error: Error?) -> Void)?
    ) async -> (drafts: [GeneratedCardDraft], lastError: Error?) {
        let total = jobs.count
        var allDrafts: [GeneratedCardDraft] = []
        let draftsPerWord = requiredCardType == nil && mode == .full ? 2 : 1
        allDrafts.reserveCapacity(total * maxWordsPerRequest * draftsPerWord)
        var lastError: Error?
        var completed = 0

        await withTaskGroup(of: (job: GenerationJob, result: Result<[GeneratedCardDraft], Error>).self) { group in
            var nextIndex = 0
            var inFlight = 0

            func enqueueAvailable() {
                while inFlight < maxConcurrentRequests, nextIndex < jobs.count {
                    let job = jobs[nextIndex]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        await MainActor.run {
                            onBatchStarted?(job.sentence, job.words)
                        }
                        do {
                            let drafts = try await generateForSingleContext(
                                sentence: job.sentence,
                                words: job.words,
                                sourceHint: sourceHint,
                                deckName: deckName,
                                mode: mode,
                                requiredCardType: requiredCardType,
                                revisionHint: nil
                            )
                            return (job, .success(drafts))
                        } catch {
                            return (job, .failure(mapTransportError(error)))
                        }
                    }
                }
            }

            enqueueAvailable()

            for await item in group {
                inFlight -= 1
                switch item.result {
                case .success(let drafts):
                    allDrafts.append(contentsOf: drafts)
                    await MainActor.run {
                        onBatchFinished?(item.job.sentence, item.job.words, drafts, nil)
                    }
                case .failure(let error):
                    lastError = error
                    await MainActor.run {
                        onBatchFinished?(item.job.sentence, item.job.words, [], error)
                    }
                }
                completed += 1
                await MainActor.run { onProgress?(completed, total) }
                enqueueAvailable()
            }
        }

        return (allDrafts, lastError)
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
        // Attach unmatched words to the shortest sentence unit to limit front-text bloat.
        let targetIndex = units.indices.min(by: { units[$0].sentence.count < units[$1].sentence.count }) ?? 0
        units[targetIndex].words.append(contentsOf: missing)
        return units
    }

    /// Replace one preview draft using the user's keep/drop reason.
    static func regenerate(
        draft: GeneratedCardDraft,
        reason: CardReplaceReason,
        deckName: String? = nil
    ) async throws -> GeneratedCardDraft {
        guard APISettings.canUseAI else {
            throw KimiCardGeneratorError.missingAPIKey
        }
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !sentence.isEmpty else {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        let drafts = try await generateForSingleContext(
            sentence: sentence,
            words: [word],
            sourceHint: draft.sourceAttribution,
            deckName: usefulDeckName(deckName),
            mode: .compact,
            requiredCardType: draft.cardType,
            revisionHint: reason.promptInstruction
        )
        guard var next = drafts.first(where: {
            $0.cardType == draft.cardType
                && $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) ?? drafts.first(where: {
            $0.word.caseInsensitiveCompare(word) == .orderedSame
        }) else {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
        next.sourceImagePath = draft.sourceImagePath
        next.isSelected = true
        next.isRecommended = true
        return next
    }

    private static func generateForSingleContext(
        sentence: String,
        words: [String],
        sourceHint: String?,
        deckName: String?,
        mode: CardGenerationMode,
        requiredCardType: CardType?,
        revisionHint: String?
    ) async throws -> [GeneratedCardDraft] {
        try await withRetry(attempts: 2) {
            let content = try await requestCards(
                sentence: sentence,
                words: words,
                sourceHint: sourceHint,
                deckName: deckName,
                mode: mode,
                requiredCardType: requiredCardType,
                revisionHint: revisionHint
            )
            return try parseCards(
                from: content,
                sentence: sentence,
                mode: mode,
                requiredCardType: requiredCardType
            )
        }
    }

    private static func withRetry<T>(
        attempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...max(attempts, 1) {
            do {
                return try await operation()
            } catch {
                let mapped = mapTransportError(error)
                lastError = mapped
                let retryable = shouldRetry(mapped)
                if !retryable || attempt == attempts {
                    throw mapped
                }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        throw lastError ?? KimiCardGeneratorError.invalidResponse
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let kimi = error as? KimiCardGeneratorError {
            switch kimi {
            case .timedOut, .parseError, .invalidResponse:
                return true
            case .apiError(let message):
                if CloudAIQuota.looksLike(message) { return false }
                let lower = message.lowercased()
                return lower.contains("timeout")
                    || lower.contains("timed out")
                    || lower.contains("rate")
                    || lower.contains("429")
                    || lower.contains("503")
                    || lower.contains("502")
            case .missingAPIKey, .allDuplicates, .quotaInsufficient:
                return false
            }
        }
        if let url = error as? URLError {
            return url.code == .timedOut
                || url.code == .networkConnectionLost
                || url.code == .notConnectedToInternet
        }
        return false
    }

    private static func mapTransportError(_ error: Error) -> Error {
        if let kimi = error as? KimiCardGeneratorError {
            return kimi
        }
        if let url = error as? URLError, url.code == .timedOut {
            return KimiCardGeneratorError.timedOut
        }
        if error is DecodingError {
            return KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
        return error
    }

    private static func requestCards(
        sentence: String,
        words: [String],
        sourceHint: String?,
        deckName: String?,
        mode: CardGenerationMode,
        requiredCardType: CardType?,
        revisionHint: String? = nil
    ) async throws -> String {
        guard let url = URL(string: APISettings.chatCompletionsURL) else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        APISettings.applyChatHeaders(to: &request)
        if APISettings.usesCloudProxy {
            request.setValue(String(max(words.count, 1)), forHTTPHeaderField: "X-KnoWell-Units")
        }

        let wordsList = words.joined(separator: ", ")
        let cardCountRule: String
        let primaryFieldHint: String
        if let requiredCardType {
            cardCountRule = """
            1. 每个生词只生成 1 张 type 为 \(requiredCardType.rawValue) 的卡（\(requiredCardType.displayName)）；禁止生成其它 type
            """
            primaryFieldHint = ""
        } else {
            switch mode {
            case .compact:
                cardCountRule = """
                1. 每个生词只生成 1 张卡；智能选择 type（cloze 或 definition）：
                   - 默认优先 cloze（语境回忆、主动提取）
                   - 以下情况选 definition：固定搭配/短语需整体记忆、抽象概念首次接触、挖空后无法辨识、原句极短
                """
                primaryFieldHint = ""
            case .full:
                cardCountRule = """
                1. 每个生词生成 2 张卡：一张 cloze，一张 definition；同一生词两张卡的 usage_note / etymology / synonyms / antonyms / paraphrases 应一致
                   - 用 primary: true 标记 AI 更推荐的一张（通常 cloze）；另一张 primary: false
                """
                primaryFieldHint = """
                  "primary": true,
                """
            }
        }

        let systemPrompt = """
        你是多语言精读助手。用户给出原句与生词/短语，请结合语境生成复习卡片：不仅解释「是什么意思」，还要分析「为何用这个词、换别的词会怎样」，补充可迁移仿写句与同义/反义汇总，并在有把握时补充词根/构词。
        必须只返回 JSON，不要 markdown，不要额外说明。
        JSON 格式：
        {
          "source": "出处（书名/文章/作者等；不确定则空字符串）",
          "cards": [
            {
              "word": "生词",
              "phonetic": "音标（英文必须给 IPA，用 /.../ 包裹；其它语言给读法；实在没有才空字符串）",
        \(primaryFieldHint)              "type": "cloze 或 definition",
              "front": "卡片正面",
              "back": "词性 + 本句核心中文释义（尽量 1 句，最多 2 句）",
              "context_note": "整句中文翻译（目标词短译必须用【】标出）",
              "highlight": "目标词在译文中的短译（须能在 context_note 中原样找到）",
              "usage_note": "用法洞察（中文，2–4 短句）：为何用此词；与 1 个近义的核心差异即可；禁止铺垫与词表罗列",
              "etymology": "词根/词缀一行拆解（有助记忆时填写；否则空字符串）",
              "synonyms": ["近义词1", "近义词2", "近义词3"],
              "antonyms": ["反义词1"],
              "paraphrases": [
                {"scene": "场景标签", "en": "一条可套用英文仿写句（含目标词）", "zh": "一句中文提示（可选）"}
              ]
            }
          ]
        }
        规则：
        \(cardCountRule)
        2. cloze 的 front：完整原句，仅把目标词/短语替换为 ______（保持原文语言）
        3. definition 的 front：必须是完整原句且保留目标词，禁止只写单词，禁止写成「xxx 是什么意思」之类提问
        4. back：只写词性 + 本句语境下的核心释义；尽量 1 句，最多 2 句；不要写整句翻译，不要把近义对比塞进 back
        5. usage_note（重要·宜短）：中文 2–4 短句，只讲「为何选此词」与 1 个替代词的关键差异（语域/语气/精确度）；禁止冗长铺垫、禁止词表、禁止复述释义
        6. synonyms：最多 3 个核心近义/可替换词（原文语言）；可带极短中文括号；没有则 []
        7. antonyms：最多 2 个反义/对立项；没有则 []
        8. paraphrases：恰好 1–2 条、不同场景各 1 句。scene 用简短中文标签；en 须含目标词且可迁移；zh 一句即可（可空）。禁止复述原著句、禁止每场景多句
        9. etymology：一行词根/词缀拆解即可；无把握空字符串，禁止编造
        10. context_note（硬性）：必须是完整一句中文翻译。目标词对应译法必须用全角【】标出，且只标一处；【】内通常 1–6 个汉字的短译，禁止标整句或整段结果状语。正确例：政府试图【缓解】其影响。/ 他【离开时】带着苦笑。错误例：未使用【】、用 []/**/「」、或【离开时不仅好笑还更聪明】这种过长标注
        11. highlight（硬性）：填写与【】内相同的短译纯文本（不要带括号）；必须是 context_note 去掉【】后仍能原样找到的子串
        12. phonetic：每个 card 都必须填写；拉丁字母词用 IPA（例 /ˈtren.tʃənt/），日语用假名/罗马音，其它语言给常用注音；禁止把音标写进 back/front
        13. 原文是什么语言，front 中的句子就保持什么语言，不要擅自翻译原句
        14. source：若能从原文、页面提示、词库名称或公认名句较有把握地判断出处（书名、篇章名、作者），填写简洁标注，如「Poor Charlie's Almanack · Charles T. Munger」；无把握必须返回空字符串，禁止编造
        15. 若提供了词库名称：把它当作主题/书名/学习范围线索，优先按该语境理解生词与【】译法；词库名 alone 不足以确定出处时不要编造 source
        16. 篇幅优先：宁短勿长，输出完整合法 JSON，不要截断
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
        if let revisionHint, !revisionHint.isEmpty {
            userPrompt += "\n重做要求：\(revisionHint)\n请给出与上一版明显不同的 front/back/usage_note，不要只改几个字。"
        }

        let body: [String: Any] = [
            "model": APISettings.effectiveModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": APISettings.chatTemperature(preferred: 0.3),
            "max_tokens": maxOutputTokens,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw KimiCardGeneratorError.invalidResponse
        }
        CloudAIQuota.ingest(http: http, data: data)

        if http.statusCode != 200 {
            let raw = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            let message = CloudAIQuota.mappedMessage(statusCode: http.statusCode, raw: raw) ?? raw
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

        // Truncated completions often yield broken JSON → surface as format error / retry.
        if let finish = first["finish_reason"] as? String,
           finish == "length" {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        return content
    }

    static func testConnection(apiKey: String, model: String) async throws {
        if APISettings.usesCloudProxy {
            guard let url = URL(string: KnoWellCloud.healthURL) else {
                throw KimiCardGeneratorError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let message = extractErrorMessage(from: data) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                throw KimiCardGeneratorError.apiError(message)
            }
            _ = model
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw KimiCardGeneratorError.missingAPIKey
        }

        guard let url = URL(string: APISettings.modelsURL) else {
            throw KimiCardGeneratorError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        APISettings.applyChatHeaders(to: &request)

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

    private static func parseCards(
        from content: String,
        sentence: String,
        mode: CardGenerationMode,
        requiredCardType: CardType?
    ) throws -> [GeneratedCardDraft] {
        let jsonString = extractJSON(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        let response: KimiCardsResponse
        do {
            response = try JSONDecoder().decode(KimiCardsResponse.self, from: data)
        } catch {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }
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
                usageNote: item.usageNote?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                etymology: item.etymology?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                synonyms: CardContentFormatter.joinRelatedWords(item.synonyms?.values ?? []),
                antonyms: CardContentFormatter.joinRelatedWords(item.antonyms?.values ?? []),
                paraphrases: CardContentFormatter.encodeParaphrases(item.decodedParaphrases),
                sourceAttribution: source,
                isSelected: selectionForItem(item, mode: mode, requiredCardType: requiredCardType),
                isRecommended: recommendationForItem(item, mode: mode, requiredCardType: requiredCardType)
            )
        }

        var filtered = drafts
        if let requiredCardType {
            filtered = drafts.filter { $0.cardType == requiredCardType }
        }

        guard !filtered.isEmpty else {
            throw KimiCardGeneratorError.parseError(L10n.generateFormatErrorDetail)
        }

        // Cloze/definition pair: copy phonetic if one sibling omitted it.
        var phoneticByWord: [String: String] = [:]
        for draft in filtered {
            if let phonetic = draft.phonetic, !phonetic.isEmpty {
                phoneticByWord[draft.word.lowercased()] = phonetic
            }
        }
        for index in filtered.indices {
            if filtered[index].phonetic == nil,
               let shared = phoneticByWord[filtered[index].word.lowercased()] {
                filtered[index].phonetic = shared
            }
        }

        switch mode {
        case .compact:
            if requiredCardType == nil {
                filtered = CardContentFormatter.expandOptionalSiblings(filtered)
            }
        case .full:
            break
        }

        return filtered
    }

    private static func selectionForItem(
        _ item: KimiCardItem,
        mode: CardGenerationMode,
        requiredCardType: CardType?
    ) -> Bool {
        if requiredCardType != nil {
            return true
        }
        switch mode {
        case .compact:
            return true
        case .full:
            if let primary = item.primary {
                return primary
            }
            return true
        }
    }

    private static func recommendationForItem(
        _ item: KimiCardItem,
        mode: CardGenerationMode,
        requiredCardType: CardType?
    ) -> Bool {
        if requiredCardType != nil {
            return true
        }
        switch mode {
        case .compact:
            return true
        case .full:
            if let primary = item.primary {
                return primary
            }
            return item.type.lowercased() == CardType.cloze.rawValue
        }
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

private struct KimiCardsResponse: Decodable {
    let source: String?
    let cards: [KimiCardItem]
}

private struct KimiCardItem: Decodable {
    let word: String
    let phonetic: String?
    let primary: Bool?
    let type: String
    let front: String
    let back: String
    let contextNote: String?
    let highlight: String?
    let usageNote: String?
    let etymology: String?
    let synonyms: FlexibleStringList?
    let antonyms: FlexibleStringList?
    let paraphrases: [KimiParaphraseItem]?

    enum CodingKeys: String, CodingKey {
        case word, phonetic, primary, type, front, back, highlight, etymology
        case synonyms, antonyms, paraphrases
        case contextNote = "context_note"
        case usageNote = "usage_note"
    }

    var decodedParaphrases: [CardParaphrase] {
        (paraphrases ?? []).compactMap { item in
            let sentence = (item.en ?? item.sentence ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return nil }
            let scene = (item.scene ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (item.zh ?? item.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CardParaphrase(
                scene: scene,
                sentence: sentence,
                note: note.isEmpty ? nil : note
            )
        }
    }
}

private struct KimiParaphraseItem: Decodable {
    let scene: String?
    let en: String?
    let sentence: String?
    let zh: String?
    let note: String?
}

/// Accepts JSON array `["a","b"]` or a single string `"a, b"`.
private struct FlexibleStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
            return
        }
        if let text = try? container.decode(String.self) {
            values = CardContentFormatter.splitRelatedWords(text)
            return
        }
        values = []
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

private extension Array {
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
