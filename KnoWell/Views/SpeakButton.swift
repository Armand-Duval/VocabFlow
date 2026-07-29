import SwiftUI

struct SpeakButton: View {
    let text: String
    var label: String?

    var body: some View {
        Button {
            SpeechService.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body)
                .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? L10n.speakWord)
    }
}
