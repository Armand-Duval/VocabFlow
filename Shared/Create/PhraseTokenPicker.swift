import SwiftUI

struct PhraseToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let range: Range<String.Index>
}

enum PhraseTokenizer {
    static func tokens(in sentence: String) -> [PhraseToken] {
        var result: [PhraseToken] = []
        var nextID = 0
        sentence.enumerateSubstrings(
            in: sentence.startIndex..<sentence.endIndex,
            options: [.byWords, .localized]
        ) { substring, substringRange, _, _ in
            guard let substring, !substring.isEmpty else { return }
            result.append(PhraseToken(id: nextID, text: substring, range: substringRange))
            nextID += 1
        }
        return result
    }

    static func phrase(in sentence: String, tokens: [PhraseToken], tokenRange: Range<Int>) -> String {
        guard !tokens.isEmpty,
              tokenRange.lowerBound >= 0,
              tokenRange.upperBound <= tokens.count,
              tokenRange.lowerBound < tokenRange.upperBound
        else { return "" }

        let start = tokens[tokenRange.lowerBound].range.lowerBound
        let end = tokens[tokenRange.upperBound - 1].range.upperBound
        return String(sentence[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Longest-first match of each vocabulary word onto consecutive tokens.
    static func matchedRanges(
        words: [String],
        tokens: [PhraseToken],
        sentence: String
    ) -> [(wordIndex: Int, tokenRange: Range<Int>)] {
        guard !words.isEmpty, !tokens.isEmpty else { return [] }

        var occupied = Set<Int>()
        var matches: [(wordIndex: Int, tokenRange: Range<Int>)] = []

        let candidates: [(wordIndex: Int, word: String)] = words.enumerated()
            .map { ($0.offset, $0.element) }
            .sorted { $0.word.count > $1.word.count }

        for candidate in candidates {
            let needle = candidate.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }

            if let range = firstMatch(of: needle, in: tokens, sentence: sentence, avoiding: occupied) {
                occupied.formUnion(range)
                matches.append((candidate.wordIndex, range))
            }
        }

        return matches.sorted { $0.tokenRange.lowerBound < $1.tokenRange.lowerBound }
    }

    private static func firstMatch(
        of needle: String,
        in tokens: [PhraseToken],
        sentence: String,
        avoiding occupied: Set<Int>
    ) -> Range<Int>? {
        guard !tokens.isEmpty, !needle.isEmpty else { return nil }

        var searchStart = sentence.startIndex
        while searchStart < sentence.endIndex,
              let found = sentence.range(
                of: needle,
                options: .caseInsensitive,
                range: searchStart..<sentence.endIndex
              ) {
            if let span = tokenSpan(covering: found, in: tokens),
               span.allSatisfy({ !occupied.contains($0) }),
               phrase(in: sentence, tokens: tokens, tokenRange: span)
                .caseInsensitiveCompare(needle) == .orderedSame {
                return span
            }
            searchStart = sentence.index(after: found.lowerBound)
        }
        return nil
    }

    private static func tokenSpan(
        covering charRange: Range<String.Index>,
        in tokens: [PhraseToken]
    ) -> Range<Int>? {
        var start: Int?
        var end: Int?
        for (index, token) in tokens.enumerated() {
            if token.range.overlaps(charRange) {
                if start == nil { start = index }
                end = index
            } else if start != nil {
                break
            }
        }
        guard let start, let end else { return nil }
        return start..<(end + 1)
    }
}

/// Sentence token chips: drag across words to merge a phrase; drag end handles to retune boundaries.
struct PhraseTokenPicker: View {
    let sentence: String
    @Binding var words: [String]
    var maxContentHeight: CGFloat? = 220
    var showsChrome: Bool = true
    var onCommitPhrase: (String) -> VocabularyWordAddResult

    @State private var tokens: [PhraseToken] = []
    @State private var dragSelection: Range<Int>?
    @State private var adjustingWordIndex: Int?
    @State private var adjustingRange: Range<Int>?
    @State private var adjustEdge: AdjustEdge?
    @State private var tokenFrames: [Int: CGRect] = [:]
    @State private var matchedRanges: [(wordIndex: Int, tokenRange: Range<Int>)] = []
    @State private var committedTokenIDs: Set<Int> = []

    private enum AdjustEdge {
        case leading
        case trailing
    }

    private var activeRange: Range<Int>? {
        adjustingRange ?? dragSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if showsChrome {
                Text(L10n.createPhrasePickerTitle)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
            }

            Group {
                if let maxContentHeight {
                    ScrollView {
                        tokenFlow
                    }
                    .frame(maxHeight: maxContentHeight)
                } else {
                    tokenFlow
                }
            }
            .onPreferenceChange(TokenFramePreferenceKey.self) { frames in
                if frames != tokenFrames {
                    tokenFrames = frames
                }
            }
            .simultaneousGesture(selectionDragGesture)

            if let range = activeRange {
                boundaryToolbar(for: range)
            }
        }
        .onAppear {
            rebuildTokens()
            refreshMatches()
        }
        .onChange(of: sentence) { _, _ in
            rebuildTokens()
            clearTransientSelection()
            refreshMatches()
        }
        .onChange(of: words) { _, _ in
            refreshMatches()
        }
    }

    private var tokenFlow: some View {
        PhraseTokenFlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(tokens) { token in
                tokenChip(token)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TokenFramePreferenceKey.self,
                                value: [token.id: geo.frame(in: .global)]
                            )
                        }
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func tokenChip(_ token: PhraseToken) -> some View {
        let inActive = activeRange?.contains(token.id) == true
        let inCommitted = committedTokenIDs.contains(token.id)
        let showingHandles = activeRange != nil
        let isLeadingHandle = showingHandles && activeRange?.lowerBound == token.id
        let isTrailingHandle = showingHandles && activeRange.map { $0.upperBound - 1 == token.id } == true

        Text(token.text)
            .font(AppFont.secondary().weight(inActive || inCommitted ? .semibold : .regular))
            .foregroundStyle(chipForeground(inActive: inActive, inCommitted: inCommitted))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(chipBackground(inActive: inActive, inCommitted: inCommitted))
            )
            .overlay(alignment: .leading) {
                if isLeadingHandle {
                    boundaryHandle(edge: .leading)
                        .offset(x: -10)
                }
            }
            .overlay(alignment: .trailing) {
                if isTrailingHandle {
                    boundaryHandle(edge: .trailing)
                        .offset(x: 10)
                }
            }
            .onTapGesture {
                handleTap(token)
            }
    }

    private func boundaryHandle(edge: AdjustEdge) -> some View {
        Circle()
            .fill(AppColor.accent)
            .frame(width: 14, height: 14)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        beginOrUpdateAdjust(edge: edge, location: value.location, translation: value.translation)
                    }
                    .onEnded { _ in
                        commitAdjustment()
                    }
            )
            .accessibilityLabel(edge == .leading ? L10n.createPhraseBoundaryStart : L10n.createPhraseBoundaryEnd)
    }

    private func boundaryToolbar(for range: Range<Int>) -> some View {
        let phrase = PhraseTokenizer.phrase(in: sentence, tokens: tokens, tokenRange: range)
        let isAdjustingExisting = adjustingWordIndex != nil

        return HStack(spacing: AppSpacing.sm) {
            Text(phrase)
                .font(AppFont.secondary().weight(.medium))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.cancel) {
                clearTransientSelection()
            }
            .font(AppFont.helper())
            .foregroundStyle(AppColor.textSecondary)

            if isAdjustingExisting {
                Text(L10n.createPhraseBoundaryHint)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textTertiary)
            } else {
                Button(L10n.createAddWord) {
                    commitPhrase(phrase)
                    clearTransientSelection()
                }
                .font(AppFont.helper().weight(.semibold))
                .foregroundStyle(AppColor.accent)
                .disabled(phrase.isEmpty)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(
            AppColor.surfaceMuted,
            in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
        )
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard adjustingWordIndex == nil else { return }
                let startID = tokenID(at: value.startLocation)
                let currentID = tokenID(at: value.location)
                guard let startID, let currentID else { return }
                let lower = min(startID, currentID)
                let upper = max(startID, currentID) + 1
                dragSelection = lower..<upper
            }
            .onEnded { _ in
                // Keep pending selection — wait for Add / Cancel.
                guard adjustingWordIndex == nil else { return }
                guard dragSelection != nil else { return }
            }
    }

    private func handleTap(_ token: PhraseToken) {
        if let match = matchedRanges.first(where: { $0.tokenRange.contains(token.id) }) {
            adjustingWordIndex = match.wordIndex
            adjustingRange = match.tokenRange
            dragSelection = nil
            return
        }

        // Tap the same pending single-token selection again to cancel.
        if dragSelection == token.id..<(token.id + 1) {
            clearTransientSelection()
            return
        }

        adjustingWordIndex = nil
        adjustingRange = nil
        dragSelection = token.id..<(token.id + 1)
    }

    private func beginOrUpdateAdjust(edge: AdjustEdge, location: CGPoint, translation: CGSize) {
        let currentRange: Range<Int>?
        if adjustingWordIndex != nil {
            currentRange = adjustingRange
        } else {
            currentRange = dragSelection
        }
        guard var range = currentRange else { return }

        adjustEdge = edge
        let probe: CGPoint
        if let frame = tokenFrames[edge == .leading ? range.lowerBound : range.upperBound - 1] {
            probe = CGPoint(
                x: frame.midX + translation.width,
                y: frame.midY + translation.height
            )
        } else {
            probe = location
        }

        guard let hovered = tokenID(at: probe) else { return }
        switch edge {
        case .leading:
            let newLower = min(hovered, range.upperBound - 1)
            range = newLower..<range.upperBound
        case .trailing:
            let newUpper = max(hovered + 1, range.lowerBound + 1)
            range = range.lowerBound..<newUpper
        }

        if adjustingWordIndex != nil {
            adjustingRange = range
        } else {
            dragSelection = range
        }
    }

    private func commitAdjustment() {
        guard let wordIndex = adjustingWordIndex,
              let range = adjustingRange,
              words.indices.contains(wordIndex)
        else {
            adjustEdge = nil
            return
        }

        let phrase = PhraseTokenizer.phrase(in: sentence, tokens: tokens, tokenRange: range)
        guard !phrase.isEmpty else {
            adjustEdge = nil
            return
        }

        let duplicate = words.enumerated().contains { index, word in
            index != wordIndex && word.caseInsensitiveCompare(phrase) == .orderedSame
        }
        if !duplicate {
            words[wordIndex] = phrase
        }
        adjustingRange = range
        adjustEdge = nil
    }

    private func commitPhrase(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = onCommitPhrase(trimmed)
    }

    private func tokenID(at globalPoint: CGPoint) -> Int? {
        tokenFrames
            .sorted { $0.key < $1.key }
            .first { _, frame in
                frame.insetBy(dx: -4, dy: -8).contains(globalPoint)
            }?
            .key
    }

    private func rebuildTokens() {
        tokens = PhraseTokenizer.tokens(in: sentence)
    }

    private func refreshMatches() {
        let matches = PhraseTokenizer.matchedRanges(words: words, tokens: tokens, sentence: sentence)
        matchedRanges = matches
        var ids = Set<Int>()
        ids.reserveCapacity(matches.reduce(0) { $0 + $1.tokenRange.count })
        for match in matches {
            ids.formUnion(match.tokenRange)
        }
        committedTokenIDs = ids
    }

    private func clearTransientSelection() {
        dragSelection = nil
        adjustingWordIndex = nil
        adjustingRange = nil
        adjustEdge = nil
    }

    private func chipForeground(inActive: Bool, inCommitted: Bool) -> Color {
        if inActive { return AppColor.accentStrong }
        if inCommitted { return AppColor.textPrimary }
        return AppColor.textBody
    }

    private func chipBackground(inActive: Bool, inCommitted: Bool) -> Color {
        if inActive { return AppColor.accentBackground(0.22) }
        if inCommitted { return AppColor.accentBackground(0.12) }
        return AppColor.surfaceMuted
    }
}

private struct TokenFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PhraseTokenFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

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
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight), frames)
    }
}
