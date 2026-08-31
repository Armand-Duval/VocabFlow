import Foundation

public struct CardParaphrase: Equatable, Identifiable, Sendable {
    public var id: String { "\(scene)|\(sentence)" }
    public var scene: String
    public var sentence: String
    public var note: String?

    public init(scene: String, sentence: String, note: String? = nil) {
        self.scene = scene
        self.sentence = sentence
        self.note = note
    }
}
