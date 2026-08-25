import Foundation

public enum DailyReflectionPrompt {
    public static let system = """
        你是克制的阅读陪伴助手，为学习 App「致知」挑选「今日一句」。
        只返回 JSON，不要 markdown，不要代码块，不要任何字段外的说明文字。

        格式：
        {
          "sentence": "原文（作品本来的语言与写法）",
          "translation": "中文翻译；原文已是现代汉语则必须空字符串",
          "source": "与 sentence 同语言的出处；不确定则空字符串",
          "source_zh": "sentence 为外文/文言时的中文出处；现代汉语原文可空字符串",
          "occasion": "极短缘由；没有则空字符串，最多 12 字"
        }

        【格式禁令 — 违反任一条视为无效输出】
        1. 禁止用斜杠 / 表示换行、分隔、占位或「或者」；sentence 与 translation 内不得出现 /
        2. 禁止把 \\n、/n 当作文字写进 sentence 或 translation；需要换行时在 JSON 字符串里写真实换行符
        3. 禁止 markdown（**、__、#、```、>）及 HTML 标签
        4. 禁止竖线 |、制表符、多余空行、首尾空格
        5. 禁止在 sentence/translation 里写出处；出处只放在 source / source_zh
        6. 禁止把翻译放进 sentence，或把外文原文只放在 translation

        【换行 — 何时用、何时不用】
        - 默认：sentence 与 translation 都是单行字符串，不含换行符
        - 仅当原文本身是短诗、且分行是作品固有形式时，才在 JSON 内用真实换行
        - 散文、戏剧台词、哲言、小说摘录：即使出自 blank verse，也写成一整句，不要人为拆行
        - 禁止为排版把句中词拆到新行；禁止因换行把句中 as/is/and 等改成行首大写

        【诗歌换行 — 仅短诗可用】
        - 正确（两行诗，分行是作品形式）：
          "sentence": "The world is too much with us; late and soon,\\nGetting and spending, we lay waste our powers;—"
        - 正确（散文/戏剧，单行）：
          "sentence": "We are such stuff as dreams are made on, and our little life is rounded with a sleep."
        - 错误（禁止人为诗化散文）：把上一句拆成三行且 As/Is 大写
        - 错误（禁止）："……soon, / Getting……" 或 "……早晚，/ 获取……"

        【出处 — 正确做法】
        - 外文原文：source 用外文（如 William Wordsworth, The World Is Too Much With Us），source_zh 用中文
        - 中文原文：source 用中文（如《论语·为政》），source_zh 留空

        选句优先级：今日节气与物候优先。季节是主约束，不是点缀：选一句读起来就像写于这个时节的原文。不要往原文里硬塞「春夏秋冬」或节气名；也禁止选与当前时令明显相反的名句（盛夏不选踏雪，深冬不选荷花盛开）。

        其他规则：
        1. sentence 必须是可核对的原文，不超过约 120 字符
        2. 现代汉语原文：translation 留空
        3. 外文原文：translation 必须是完整中文翻译，缺翻译视为无效
        4. source / source_zh 无把握则空字符串，禁止编造
        5. 不要鸡汤口号、不要催学习、不要广告
        6. 连续多日必须换作品（或同一作家的另一部作品）；禁止连续使用同一原文
        7. 用户关键词只限制从哪类作品或语言里选，不能压过时令，也不能把关键词塞进句子
        8. 禁止复述近期已展示原文；宁可选较冷门、仍可核对的一句，也不要再拿各语言里被引到滥的那几句
        """

    public struct Input: Equatable, Sendable {
        public var dateText: String
        public var day: Date
        public var localeID: String
        public var preferenceSnippet: String?
        public var excludedSentences: [String]
        public var excludedSources: [String]
        public var isManualRefresh: Bool
        public var refreshAttempt: Int
        public var retryBoost: Bool

        public init(
            dateText: String,
            day: Date,
            localeID: String,
            preferenceSnippet: String? = nil,
            excludedSentences: [String] = [],
            excludedSources: [String] = [],
            isManualRefresh: Bool = false,
            refreshAttempt: Int = 1,
            retryBoost: Bool = false
        ) {
            self.dateText = dateText
            self.day = day
            self.localeID = localeID
            self.preferenceSnippet = preferenceSnippet
            self.excludedSentences = excludedSentences
            self.excludedSources = excludedSources
            self.isManualRefresh = isManualRefresh
            self.refreshAttempt = refreshAttempt
            self.retryBoost = retryBoost
        }

        public var hasKeywords: Bool {
            guard let preferenceSnippet else { return false }
            return !preferenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public static func user(_ input: Input, calendar: Calendar = .current) -> String {
        """
        今天：\(input.dateText)
        \(seasonalBlock(for: input.day, calendar: calendar))
        用户地区标识：\(input.localeID)
        \(preferenceHint(for: input))
        \(refreshHint(for: input))
        \(retrySeasonHint(for: input))

        请给出今日一句。要求：
        - sentence 是作品原文（本来是什么语言就用什么语言）
        - 外文原文必须另给完整中文 translation；现代汉语原文 translation 留空
        - 先贴合今日节气/物候选句；换一部与近期不同的作品
        - 默认单行输出；只有短诗且分行是原文形式时才用真实换行，散文/戏剧台词不要拆行
        - 外文必须同时给出外文 source 与中文 source_zh
        - occasion 可用极短节气或物候（如「处暑将至」），不要写成天气预报
        """
    }

    public static func preferredTemperature(_ input: Input) -> Double {
        if input.isManualRefresh {
            return input.retryBoost ? 1.0 : 0.92
        }
        if input.retryBoost || input.hasKeywords {
            return 0.85
        }
        return 0.82
    }

    /// Approximate northern-hemisphere solar term by month-day; good enough for prompt flavor.
    public static func seasonalBlock(for day: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: day)
        let monthDay = calendar.component(.day, from: day)
        let stamp = month * 100 + monthDay

        let indexed = solarTerms.enumerated().map { index, term in
            (index: index, stamp: term.month * 100 + term.day, term: term)
        }
        let current = indexed.last { $0.stamp <= stamp } ?? indexed.last!
        let next = indexed[(current.index + 1) % indexed.count]
        let season: String
        switch month {
        case 3, 4, 5: season = month == 3 ? "初春" : (month == 4 ? "仲春" : "暮春")
        case 6, 7, 8: season = month == 6 ? "初夏" : (month == 7 ? "盛夏" : "夏末")
        case 9, 10, 11: season = month == 9 ? "仲秋" : (month == 10 ? "深秋" : "秋末")
        default: season = month == 12 ? "仲冬" : (month == 1 ? "深冬" : "冬末春将至")
        }

        return """
        季节：\(season)
        当前节气：\(current.term.name)
        下一节气：\(next.term.name)
        物候线索：\(current.term.phenology)
        选句须有这个时节的气息，不要选相反时令的名句。
        """
    }

    private static func preferenceHint(for input: Input) -> String {
        if let snippet = input.preferenceSnippet, input.hasKeywords {
            return """
            用户口味关键词：\(snippet)。这是选书/选作者的范围，不是造句素材。
            - 只从符合这一语言或文体气质的作品里选一句可核对的原文
            - 今日节气与物候仍优先于关键词；禁止把关键词塞进 sentence
            - 外文原文必须同时给出完整中文 translation
            - 今天必须换一部与近期不同的作品
            """
        }
        return """
        用户未设置口味关键词。只按今日节气物候选句，仍须换作品。
        原文在前；外文必须另给中文翻译。
        """
    }

    private static func refreshHint(for input: Input) -> String {
        let exclusion = exclusionBlock(
            sentences: input.excludedSentences,
            sources: input.excludedSources
        )
        if input.isManualRefresh {
            return """
            这是用户第 \(input.refreshAttempt) 次刷新今日一句：必须换一句与下方列表完全不同的经典名句。
            禁止重复同一原文（不要只改 translation/source）；必须换作品。
            \(exclusion)
            """
        }
        return """
        这是今日首次生成。必须与近期已展示原文完全不同，并换一部作品。
        \(exclusion)
        """
    }

    private static func retrySeasonHint(for input: Input) -> String {
        input.retryBoost
            ? "上一轮疑似重复或不够贴合时令。必须换一部与近期完全不同的作品，仍须贴合今日节气物候，不要退回最著名的那一句。"
            : "季节与节气是今天选句的第一约束。"
    }

    private static func exclusionBlock(sentences: [String], sources: [String]) -> String {
        if sentences.isEmpty && sources.isEmpty {
            return "近期尚无已展示句子。"
        }
        var lines: [String] = []
        if !sentences.isEmpty {
            lines.append("近期已展示原文（禁止重复，包括只改标点/换行/节选）：")
            lines.append(contentsOf: sentences.prefix(24).enumerated().map { index, sentence in
                let preview = sentence.replacingOccurrences(of: "\n", with: " ")
                let clipped = preview.count > 80 ? String(preview.prefix(80)) + "…" : preview
                return "\(index + 1). \(clipped)"
            })
        }
        if !sources.isEmpty {
            lines.append("近期出处（今天请换作品）：")
            lines.append(contentsOf: sources.prefix(12).map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static let solarTerms: [(month: Int, day: Int, name: String, phenology: String)] = [
        (1, 6, "小寒", "地冻、岁首将尽、炭火与闭门"),
        (1, 20, "大寒", "一年最冷、残雪、闭藏"),
        (2, 4, "立春", "冰将解、草芽、东风"),
        (2, 19, "雨水", "解冻、润物、春寒未尽"),
        (3, 6, "惊蛰", "雷始、虫动、草木苏"),
        (3, 21, "春分", "昼夜均、花信、风软"),
        (4, 5, "清明", "雨、柳、踏青与追念"),
        (4, 20, "谷雨", "茶、牡丹、春深将尽"),
        (5, 6, "立夏", "清和、新绿转浓、昼长"),
        (5, 21, "小满", "麦气、晚春余温、草木盛"),
        (6, 6, "芒种", "梅近、农忙、湿热将起"),
        (6, 21, "夏至", "白昼极长、浓荫、炎热初盛"),
        (7, 7, "小暑", "盛夏、蝉、荷"),
        (7, 23, "大暑", "酷热、暴雨、伏"),
        (8, 7, "立秋", "暑始收、一叶、新凉将起"),
        (8, 23, "处暑", "残暑、晚蝉、早晚凉"),
        (9, 7, "白露", "露白、桂、秋清"),
        (9, 23, "秋分", "平分秋色、雁、叶始黄"),
        (10, 8, "寒露", "霜意、菊、衣要添"),
        (10, 23, "霜降", "霜、柿、秋深"),
        (11, 7, "立冬", "闭藏、木落、初寒"),
        (11, 22, "小雪", "薄寒、初雪或干冷"),
        (12, 7, "大雪", "冬深、夜长、火与窗"),
        (12, 22, "冬至", "一阳生、岁晚、最长的夜")
    ]
}
