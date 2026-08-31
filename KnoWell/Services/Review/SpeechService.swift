import AVFoundation

@MainActor
enum SpeechService {
    private static let synthesizer = AVSpeechSynthesizer()

    /// Speaks `text` in the language of `context` (example sentence / source), not the lone word.
    static func speak(_ text: String, context: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let hint = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let language = SourceLanguage.guess(fromSourceText: hint.isEmpty ? trimmed : hint)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        synthesizer.speak(utterance)
    }

    static func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
