import Foundation
import NaturalLanguage

/// Language of the study material, guessed from context (example sentence / source line),
/// not from a lone headword — cognates like "acquisition" misclassify as French.
public enum SourceLanguage: Equatable, Sendable {
    case english
    case french
    case german
    case spanish
    case italian
    case portuguese
    case japanese
    case simplifiedChinese
    case traditionalChinese
    case korean
    case undetermined

    public static func guess(fromSourceText text: String, extra: String? = nil) -> SourceLanguage {
        let primary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = extra?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sample: String
        if isStrongContext(primary) {
            sample = primary
        } else if isStrongContext(secondary) {
            sample = secondary
        } else {
            sample = [primary, secondary].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        guard !sample.isEmpty else { return .undetermined }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return map(recognizer.dominantLanguage)
    }

    public var speechCode: String {
        switch self {
        case .english, .undetermined: return "en-US"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .spanish: return "es-ES"
        case .italian: return "it-IT"
        case .portuguese: return "pt-BR"
        case .japanese: return "ja-JP"
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .korean: return "ko-KR"
        }
    }

    public var promptName: String {
        switch self {
        case .english: return "英语"
        case .french: return "法语"
        case .german: return "德语"
        case .spanish: return "西班牙语"
        case .italian: return "意大利语"
        case .portuguese: return "葡萄牙语"
        case .japanese: return "日语"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .korean: return "韩语"
        case .undetermined: return "原文语言"
        }
    }

    public var phoneticRule: String {
        switch self {
        case .english:
            return "英语 IPA（Cambridge / Merriam），用 /.../ 包裹；重音用 ˈ 和 ˌ，禁止直引号 '；元音用 æ ɪ ə ʌ ɑ ɔ ʊ，不要套用其它语言的读法"
        case .french:
            return "法语 IPA，用 /.../ 包裹"
        case .german:
            return "德语 IPA，用 /.../ 包裹"
        case .spanish:
            return "西班牙语 IPA，用 /.../ 包裹"
        case .italian:
            return "意大利语 IPA，用 /.../ 包裹"
        case .portuguese:
            return "葡萄牙语 IPA，用 /.../ 包裹"
        case .japanese:
            return "假名（可附罗马音）"
        case .simplifiedChinese:
            return "汉语拼音"
        case .traditionalChinese:
            return "汉语拼音或注音"
        case .korean:
            return "韩语罗马音或标准注音"
        case .undetermined:
            return "按原文语言给常用注音；拉丁字母词用该语言自己的 IPA，不要串到另一种语言"
        }
    }

    private static func isStrongContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 20 { return true }
        guard trimmed.count >= 12 else { return false }
        let tokens = trimmed.split { $0.isWhitespace || $0.isPunctuation }.filter { $0.count >= 2 }
        return tokens.count >= 3
    }

    private static func map(_ language: NLLanguage?) -> SourceLanguage {
        switch language {
        case .english: return .english
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        case .italian: return .italian
        case .portuguese: return .portuguese
        case .japanese: return .japanese
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        case .korean: return .korean
        default: return .undetermined
        }
    }
}
