import Foundation

/// Intake black box: turn a capture into vocab units or appreciation quotes.
///
/// ① Image + words → `[(sentence, words)]` (`ImageOCRService.recognize` is the photo entry)
/// ② Source text + words → `[(sentence, words)]`
/// ③ Source text, no words → quotes
/// ④ Image + sentence(s), no words → quotes (same `quotes(from:)`; image is only the photo)
///
/// Word vs sentence is not classified here. Empty word list on the create screen means ③/④.
public enum Preprocess {
    /// ① After OCR: page + vocabulary marks → units.
    public static func fromImage(
        fullText: String,
        words: [String],
        preferredUnits: [OCRImportUnit] = [],
        leftColumnWords: [String] = []
    ) -> [OCRImportUnit] {
        let textUnits = units(in: fullText, words: words)
        let chosen = preferredUnits.count > textUnits.count ? preferredUnits : textUnits
        let raw = OCRResult(
            fullText: fullText,
            highlightedWords: words,
            importUnits: chosen,
            sourceImagePath: nil,
            importKind: chosen.isEmpty ? .none : .highlight
        )
        var result = raw.sanitizedForImport()
        if result.importUnits.isEmpty,
           let page = OCRVocabPageExtractor.extract(
            fullText: result.fullText,
            leftColumnWords: leftColumnWords
           ) {
            return page.units
        }
        return result.importUnits
    }

    /// ② Source sentence(s) + words → one unit per sentence that contains words.
    public static func fromText(
        sentence: String,
        words: [String],
        imageOnlySource: Bool = false
    ) -> [OCRImportUnit] {
        OCRContextExtractor.generationUnits(
            sentence: sentence,
            words: words,
            imageOnlySource: imageOnlySource
        )
    }

    /// ③/④ One excerpt → cleaned quote (regenerate / single card). Multi-sentence → `quotes(from:)`.
    public static func fromQuote(_ text: String) -> String {
        LiteraryTextFormatting.display(text)
    }

    /// ③/④ Split into one quote per sentence (blank paragraphs too; single newlines stay for poetry).
    public static func quotes(from text: String) -> [String] {
        OCRContextExtractor.splitQuotes(text)
            .map(fromQuote)
            .filter { !$0.isEmpty }
    }

    /// Clipboard / share text: a single vocab item vs a sentence.
    public static func parsePaste(_ text: String) -> ParsedImportText {
        ImportTextAnalyzer.parse(text)
    }

    public static func units(in fullText: String, words: [String]) -> [OCRImportUnit] {
        OCRContextExtractor.importUnits(fullText: fullText, highlightedWords: words)
    }

    public static func joinedSentences(_ units: [OCRImportUnit]) -> String? {
        OCRContextExtractor.joinedImportSentences(units)
    }

    public static func displaySource(_ text: String) -> String {
        OCRContextExtractor.sourceTextForDisplay(text)
    }

    public static func sourceHint(from fullText: String) -> String? {
        OCRContextExtractor.sourceHint(from: fullText)
    }

    public static func disambiguationHint(from fullText: String, words: [String]) -> String? {
        OCRContextExtractor.disambiguationHint(from: fullText, words: words)
    }
}
