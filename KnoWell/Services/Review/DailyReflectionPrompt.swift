import Foundation

public enum DailyReflectionPrompt {
    public static let system = """
        你是文选编者，为学习 App「致知」每天只摘一句「今日一句」。
        你不写句子，只从人类已经写下的作品里摘一句可核对的原文。
        只返回 JSON，不要 markdown，不要代码块，不要任何字段外的说明文字。

        【默认气质 — 无关键词时也必须遵守】
        1. 深度，或浪漫，或二者兼有。深度是时间、有限、记忆、光线、身体；浪漫是爱、等待、物候里的舍不得。不是道理，不是甜言。
        2. 特殊视角：一个具体的人在这个时节里看见、等待、记得或舍不得。禁止全称判断式格言（「人生就是…」「真正的智慧是…」）。
        3. 必须是历史上的文字：诗、词、曲、赋、书信、日记、游记、小说、戏剧、经文、碑铭。
        4. 气质是主依据：深度或浪漫、特殊视角、可核对的历史原文。季节只是背景，用来避免反季（盛夏不选踏雪，深冬不选荷花盛开）。不需要节气名，也不要为了贴季节去找带「春夏秋冬」字的名句。

        【语言 — 绝不限定西诗】
        - 无关键词时语言完全开放，西诗只是世界文学的一种，不是主场，更不是默认。
        - 中文诗、词、曲、赋、文言、书信、日记；日文俳句；波斯、希腊罗马；英诗、法德俄诗；小说与戏剧摘录均可。
        - 禁止把默认理解成「今日一句 = 英文诗 / 西诗」。
        - 连续多日须换语言或传统；若近期已连续偏英文，今日必须改选中文（或非英语）原文。

        【严禁 — 出现即无效】
        - 励志、成功学、演讲金句、教科书「名言警句」、鸡汤、催学习、广告
        - 巴菲特、乔布斯、爱因斯坦语录，以及被译滥的苏格拉底/亚里士多德口号
        - 各语言里被引到滥的那几句（如：春眠不觉晓、知之为知之、To be or not to be、The unexamined life、海内存知己、停车坐爱枫林晚）
        - 把节气名或「春夏秋冬」硬塞进原文；禁止仿写、禁止现代网络文

        格式：
        {
          "sentence": "原文（作品本来的语言与写法）",
          "translation": "中文翻译；原文已是现代汉语则必须空字符串",
          "source": "与 sentence 同语言的出处；不确定则空字符串",
          "source_zh": "sentence 为外文/文言时的中文出处；现代汉语原文可空字符串",
          "occasion": "必须空字符串；不要写节气、季节或缘由"
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
        - 散文、戏剧台词、书信、小说摘录：即使出自 blank verse，也写成一整句，不要人为拆行
        - 禁止为排版把句中词拆到新行；禁止因换行把句中 as/is/and 等改成行首大写

        【诗歌换行 — 仅短诗可用】
        - 正确（中文两句，分行是作品形式）：
          "sentence": "君问归期未有期，\\n巴山夜雨涨秋池。"
        - 正确（外文两行诗）：
          "sentence": "The world is too much with us; late and soon,\\nGetting and spending, we lay waste our powers;—"
        - 正确（散文/戏剧，单行）：
          "sentence": "We are such stuff as dreams are made on, and our little life is rounded with a sleep."
        - 错误（禁止人为诗化散文）：把上一句拆成三行且 As/Is 大写
        - 错误（禁止）："……soon, / Getting……" 或 "……早晚，/ 获取……"

        【出处 — 正确做法】
        - 外文原文：source 用外文，source_zh 用中文
        - 中文原文：source 用中文（如李商隐《晚晴》），source_zh 留空

        其他规则：
        1. sentence 必须是可核对的原文，不超过约 120 字符
        2. 现代汉语原文：translation 留空；文言须给白话 translation
        3. 外文原文：translation 必须是完整中文翻译，缺翻译视为无效
        4. source / source_zh 无把握则空字符串，禁止编造
        5. 连续多日必须换作品（或同一作家的另一部作品）；禁止连续使用同一原文
        6. 用户关键词只限制从哪类作品或语言里选，不能把关键词塞进句子
        7. 禁止复述近期已展示原文；宁可选较冷门、仍可核对的一句，也不要再拿被引到滥的那几句
        8. occasion 必须是空字符串；禁止写节气名、季节名或天气预报
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

    public enum LiterarySeason: String, Sendable {
        case spring
        case summer
        case autumn
        case winter
    }

    public static func user(_ input: Input, calendar: Calendar = .current) -> String {
        """
        今天：\(input.dateText)
        \(seasonalBlock(for: input.day, calendar: calendar))
        用户地区标识：\(input.localeID)
        \(preferenceHint(for: input))
        \(languageBalanceHint(sentences: input.excludedSentences, hasKeywords: input.hasKeywords))
        \(refreshHint(for: input))
        \(retrySeasonHint(for: input))

        请给出今日一句。要求：
        - sentence 是作品原文（本来是什么语言就用什么语言）
        - 从历史作品里摘一句有深度或浪漫、视角具体的原文；只要不跟当前季节明显反季即可
        - 不要格言，不要最著名的那一句
        - 季节只是避免反季的背景，不是标题；不需要节气也能选句，禁止把节气名写进任何字段
        - 不要默认成英文诗或西诗；无关键词时语言开放，中文诗词与世界文学轮换
        - 外文原文必须另给完整中文 translation；文言须给白话；现代汉语原文 translation 留空
        - 默认单行输出；只有短诗且分行是原文形式时才用真实换行
        - 外文必须同时给出外文 source 与中文 source_zh
        - occasion 必须空字符串
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

    public static func literarySeason(for day: Date, calendar: Calendar = .current) -> LiterarySeason {
        switch calendar.component(.month, from: day) {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }

    /// Season as background flavor only — never a title, never a solar-term assignment.
    public static func seasonalBlock(for day: Date, calendar: Calendar = .current) -> String {
        let resolved = resolvedTerms(for: day, calendar: calendar)
        return """
        季节背景：\(resolved.seasonName)（只用来避免反季，不是选句主依据，不要写进句子或标签）
        时令气息：\(resolved.current.mood)
        不需要节气名。没有节气也能选句。主依据仍是深度或浪漫的历史原文。
        """
    }

    private static func preferenceHint(for input: Input) -> String {
        if let snippet = input.preferenceSnippet, input.hasKeywords {
            return """
            用户口味关键词：\(snippet)。这是选书/选作者/选语言的范围，不是造句素材。
            - 只从符合这一语言或文体气质的作品里选一句可核对的原文
            - 禁止把关键词塞进 sentence；不要为了贴节气而改选
            - 深度或浪漫、特殊视角，仍是底线
            - 外文原文必须同时给出完整中文 translation
            - 今天必须换一部与近期不同的作品
            """
        }
        return """
        用户未设置口味关键词。按默认气质选句：深度或浪漫、特殊视角、人类历史上的原文。
        季节只是避免反季的背景，不是主依据，不需要节气。
        语言不限，绝不是只选西诗。中文诗词、文言、书信与其他传统轮换。
        原文在前；外文必须另给中文翻译。
        """
    }

    private static func languageBalanceHint(sentences: [String], hasKeywords: Bool) -> String {
        guard !hasKeywords else {
            return "用户已指定口味。不要把未点名的语言全部排除，除非关键词本身就是某种语言。"
        }
        var latinHeavy = 0
        var hanHeavy = 0
        for sentence in sentences.prefix(8) {
            let latin = sentence.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count
            let han = sentence.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
            if latin >= 4, latin > han {
                latinHeavy += 1
            } else if han >= 2 {
                hanHeavy += 1
            }
        }
        if latinHeavy >= 2, latinHeavy > hanHeavy {
            return "近期已连续偏外文。今日必须选中文诗词、文言、曲或书信，不要再选英文诗。"
        }
        if hanHeavy >= 3, hanHeavy > latinHeavy + 1 {
            return "近期中文偏多。今日可选其他语种的历史原文，且不限于英文诗：俳句、法德诗、波斯、希腊罗马，或中文里较冷门的一句。"
        }
        return "语言不限，且绝不默认成西诗。中文与其他传统轮换。"
    }

    private static func refreshHint(for input: Input) -> String {
        let exclusion = exclusionBlock(
            sentences: input.excludedSentences,
            sources: input.excludedSources
        )
        if input.isManualRefresh {
            return """
            这是用户第 \(input.refreshAttempt) 次刷新今日一句：必须换一句与下方列表完全不同的历史原文。
            禁止重复同一原文（不要只改 translation/source）；必须换作品。气质仍须深度或浪漫。不要用刷新当借口改成英文诗专场。
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
            ? "上一轮疑似重复或像格言。必须换一部与近期完全不同的作品；仍须是深度或浪漫的历史原文，不要退回最著名的那一句，也不要改成英文诗充数。"
            : "主依据是深度或浪漫的历史原文。季节只避免反季，不需要节气。"
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

    private struct SolarTerm {
        let month: Int
        let day: Int
        let mood: String
    }

    private struct ResolvedTerms {
        let seasonName: String
        let current: SolarTerm
    }

    private static func resolvedTerms(for day: Date, calendar: Calendar) -> ResolvedTerms {
        let month = calendar.component(.month, from: day)
        let monthDay = calendar.component(.day, from: day)
        let stamp = month * 100 + monthDay
        let indexed = solarTerms.map { (stamp: $0.month * 100 + $0.day, term: $0) }
        let current = indexed.last { $0.stamp <= stamp } ?? indexed.last!
        let seasonName: String
        switch month {
        case 3, 4, 5: seasonName = month == 3 ? "初春" : (month == 4 ? "仲春" : "暮春")
        case 6, 7, 8: seasonName = month == 6 ? "初夏" : (month == 7 ? "盛夏" : "夏末")
        case 9, 10, 11: seasonName = month == 9 ? "仲秋" : (month == 10 ? "深秋" : "秋末")
        default: seasonName = month == 12 ? "仲冬" : (month == 1 ? "深冬" : "冬末春将至")
        }
        return ResolvedTerms(seasonName: seasonName, current: current.term)
    }

    private static let solarTerms: [SolarTerm] = [
        SolarTerm(month: 1, day: 6, mood: "地冻、闭门、岁将尽。"),
        SolarTerm(month: 1, day: 20, mood: "最冷、残雪、屋里的光。"),
        SolarTerm(month: 2, day: 4, mood: "冰将解、犹寒、草芽。"),
        SolarTerm(month: 2, day: 19, mood: "润、湿、春寒未尽。"),
        SolarTerm(month: 3, day: 6, mood: "初鸣、草木刚苏、夜还凉。"),
        SolarTerm(month: 3, day: 21, mood: "风软、花信、昼夜均。"),
        SolarTerm(month: 4, day: 5, mood: "雨、柳、或想起谁。"),
        SolarTerm(month: 4, day: 20, mood: "春深、花事将过。"),
        SolarTerm(month: 5, day: 6, mood: "绿转浓、昼开始长。"),
        SolarTerm(month: 5, day: 21, mood: "晚春余温、草木正盛。"),
        SolarTerm(month: 6, day: 6, mood: "梅近、湿将起。"),
        SolarTerm(month: 6, day: 21, mood: "白昼极长、浓荫。"),
        SolarTerm(month: 7, day: 7, mood: "蝉、荷、热里的倦。"),
        SolarTerm(month: 7, day: 23, mood: "酷热、雨、夜仍热。"),
        SolarTerm(month: 8, day: 7, mood: "暑还在、凉将起。"),
        SolarTerm(month: 8, day: 23, mood: "残暑、早晚开始有凉意。"),
        SolarTerm(month: 9, day: 7, mood: "清、夜凉、或有桂。"),
        SolarTerm(month: 9, day: 23, mood: "叶始黄、清秋。"),
        SolarTerm(month: 10, day: 8, mood: "将寒、要添衣。"),
        SolarTerm(month: 10, day: 23, mood: "霜、秋深。"),
        SolarTerm(month: 11, day: 7, mood: "木落、初寒、屋里。"),
        SolarTerm(month: 11, day: 22, mood: "薄寒、或初雪。"),
        SolarTerm(month: 12, day: 7, mood: "夜长、火与窗。"),
        SolarTerm(month: 12, day: 22, mood: "最长的夜、岁晚。")
    ]
}
