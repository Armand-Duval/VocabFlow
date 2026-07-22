import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
            if words.isEmpty {
                Text("拖选原文加入，或在下方手动输入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VocabularyWordFlowLayout(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        VocabularyWordChip(word: word) {
                            words.remove(at: index)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("手动输入生词", text: $manualInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isManualInputFocused)
                    .onSubmit(addManualWord)

                if !manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("添加") {
                        addManualWord()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(feedbackIsError ? .orange : .secondary)
            }
        }
    }

    func addWord(_ word: String) -> VocabularyWordAddResult {
        let result = VocabularyWords.append(word, to: &words)
        publishFeedback(for: result)
        return result
    }

    private func addManualWord() {
        let result = addWord(manualInput)
        if case .added = result {
            manualInput = ""
        }
        isManualInputFocused = false
    }

    private func publishFeedback(for result: VocabularyWordAddResult) {
        switch result {
        case let .added(word):
            feedbackMessage = "已加入「\(word)」"
            feedbackIsError = false
            haptic(.light)
        case let .duplicate(word):
            feedbackMessage = "「\(word)」已在生词列表中"
            feedbackIsError = true
            haptic(.medium)
        case .empty:
            feedbackMessage = "选区为空"
            feedbackIsError = true
            haptic(.medium)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if feedbackMessage != nil {
                feedbackMessage = nil
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

private struct VocabularyWordChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(word)
                .font(.subheadline)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

private struct VocabularyWordFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
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
