import Foundation

public enum AppreciationPrompt {
    public static let system = """
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

    public static func user(
        sentence: String,
        source: String = "",
        translation: String = "",
        occasion: String = "",
        revisionHint: String? = nil
    ) -> String {
        var prompt = """
        原文：
        \(sentence)
        """
        if !source.isEmpty {
            prompt += "\n出处：\(source)"
        }
        if !translation.isEmpty {
            prompt += "\n已有译文（可沿用）：\(translation)"
        }
        if !occasion.isEmpty {
            prompt += "\n缘由：\(occasion)"
        }
        if let revisionHint, !revisionHint.isEmpty {
            prompt += "\n重做要求：\(revisionHint)\n请换一个切入角度，不要重复上一版赏析。"
        }
        return prompt
    }
}

public struct AppreciationPayload: Equatable, Sendable {
    public var title: String?
    public var translation: String?
    public var appreciation: String?
    public var takeaway: String?

    public init(
        title: String? = nil,
        translation: String? = nil,
        appreciation: String? = nil,
        takeaway: String? = nil
    ) {
        self.title = title
        self.translation = translation
        self.appreciation = appreciation
        self.takeaway = takeaway
    }

    public var mergedAppreciation: String? {
        var text = appreciation?.nilIfEmpty ?? ""
        if let takeaway = takeaway?.nilIfEmpty {
            text = text.isEmpty ? takeaway : "\(text)\n\n\(takeaway)"
        }
        return text.nilIfEmpty
    }
}

public enum AppreciationParser {
    public static func parse(from content: String) throws -> AppreciationPayload {
        let decoded: AppreciationResponse
        do {
            decoded = try AIJSON.decode(AppreciationResponse.self, from: content)
        } catch {
            throw CardGenerationParseError.invalidJSON
        }
        return AppreciationPayload(
            title: decoded.title?.nilIfEmpty,
            translation: decoded.translation?.nilIfEmpty,
            appreciation: decoded.appreciation?.nilIfEmpty,
            takeaway: decoded.takeaway?.nilIfEmpty
        )
    }
}

private struct AppreciationResponse: Decodable {
    let title: String?
    let translation: String?
    let appreciation: String?
    let takeaway: String?
}

fileprivate extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
