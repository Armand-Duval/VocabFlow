import SwiftUI

enum VocabularyWordAddResult: Equatable {
    case added(String)
    case duplicate(String)
    case empty
}

enum VocabularyWords {
    static func parse(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func join(_ words: [String]) -> String {
        words.joined(separator: ", ")
    }

    static func append(_ word: String, to words: inout [String]) -> VocabularyWordAddResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .duplicate(trimmed)
        }
        words.append(trimmed)
        return .added(trimmed)
    }
}

struct VocabularyWordsEditor: View {
    @Binding var words: [String]
    @Binding var feedbackMessage: String?
    @Binding var feedbackIsError: Bool

    @State private var manualInput = ""
    @FocusState private var isManualInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !words.isEmpty {
                VocabularyWordFlowLayout(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        VocabularyWordChip(word: word) {
                            words.remove(at: index)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                TextField(L10n.wordsManualPlaceholder, text: $manualInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isManualInputFocused)
                    .onSubmit(addManualWord)

                if !manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(L10n.add, action: addManualWord)
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    func addWord(_ word: String) -> VocabularyWordAddResult {
        let result = VocabularyWords.append(word, to: &words)
        VocabularyWordFeedback.apply(result, message: &feedbackMessage, isError: &feedbackIsError)
        clearFeedbackLater()
        return result
    }

    private func addManualWord() {
        let result = addWord(manualInput)
        if case .added = result {
            manualInput = ""
        }
        isManualInputFocused = false
    }

    private func clearFeedbackLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            feedbackMessage = nil
        }
    }
}

private struct VocabularyWordChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.subheadline)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.cancel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

private struct VocabularyWordFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
