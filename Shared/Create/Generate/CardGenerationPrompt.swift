import Foundation

public enum CardGenerationPrompt {
    public static func system(requiredCardType: CardType?) -> String {
        let cardCountRule: String
        if let requiredCardType {
            cardCountRule = """
            1. 每个生词只生成 1 张 type 为 \(requiredCardType.rawValue) 的卡（\(requiredCardType.promptLabel)）；禁止生成其它 type
            """
        } else {
            cardCountRule = """
            1. 每个生词只生成 1 张卡；智能选择 type（cloze 或 definition）：
               - 默认优先 cloze（语境回忆、主动提取）
               - 以下情况选 definition：固定搭配/短语需整体记忆、抽象概念首次接触、挖空后无法辨识、原句极短
            """
        }

        return """
        你是多语言精读助手。用户给出原句与生词/短语，请结合语境生成复习卡片：不仅解释「是什么意思」，还要分析「为何用这个词、换别的词会怎样」，补充可迁移仿写句与同义/反义汇总，并在有把握时补充词根/构词。
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
    }

    public static func user(
        sentence: String,
        words: [String],
        deckName: String? = nil,
        sourceHint: String? = nil,
        imageOnlySource: Bool = false,
        revisionHint: String? = nil
    ) -> String {
        var prompt = """
        原文：\(sentence)
        生词：\(words.joined(separator: ", "))
        """
        if let deckName, !deckName.isEmpty {
            prompt += "\n词库名称（可能是书名、专题或学习范围；请作为释义语境与出处线索）：\(deckName)"
        }
        if let sourceHint, !sourceHint.isEmpty {
            if imageOnlySource {
                prompt += "\n判义线索（界面文字，供理解词义，不是卡片原文）：\(sourceHint)"
            } else {
                prompt += "\n页面提示（可能含书名/标题/作者，供判断出处）：\(sourceHint)"
            }
        }
        if imageOnlySource {
            prompt += "\n这是游戏/界面截图，没有完整句子。请为每个生词生成 definition 类型：front 只写生词本身，不要编造例句。"
        }
        if let revisionHint, !revisionHint.isEmpty {
            prompt += "\n重做要求：\(revisionHint)\n请给出与上一版明显不同的 front/back/usage_note，不要只改几个字。"
        }
        return prompt
    }
}

private extension CardType {
    var promptLabel: String {
        switch self {
        case .cloze: "挖空"
        case .definition: "释义"
        case .appreciation: "赏析"
        }
    }
}
