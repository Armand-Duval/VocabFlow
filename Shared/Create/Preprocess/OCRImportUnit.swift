import Foundation

/// One importable context: a sentence plus the highlighted words inside it.
public struct OCRImportUnit: Equatable, Sendable {
    public var sentence: String
    public var words: [String]

    public init(sentence: String, words: [String]) {
        self.sentence = sentence
        self.words = words
    }
}
