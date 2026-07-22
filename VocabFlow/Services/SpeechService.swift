import AVFoundation
import NaturalLanguage

@MainActor
enum SpeechService {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode(for: trimmed))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        synthesizer.speak(utterance)
    }

    static func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func languageCode(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .english:
            return "en-US"
        case .japanese:
            return "ja-JP"
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .korean:
            return "ko-KR"
        case .french:
            return "fr-FR"
        case .german:
            return "de-DE"
        case .spanish:
            return "es-ES"
        default:
            return "en-US"
        }
    }
}
