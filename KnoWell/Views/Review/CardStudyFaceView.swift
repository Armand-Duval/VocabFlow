import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Shared study face used by review and create-preview. Parents supply chrome / footer.
struct CardStudyFaceView: View {
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    let content: CardStudyContent
    @Binding var showBack: Bool
    @Binding var dragOffset: CGSize
    var allowsReviewGestures: Bool = false
    var onHighlight: ((String) -> Void)?
    var onCreateCard: ((String) -> Void)?
    var onRevealed: (() -> Void)?
    var onSwipeAgain: (() -> Void)?
    var onSwipeEasy: (() -> Void)?

    @State private var relatedWordsExpanded = false
    @State private var aiExpanded = false
    @State private var paraphrasesExpanded = false

    @AppStorage("review.hasSeenScrollHint") private var hasSeenScrollHint = false

    private let swipeThreshold: CGFloat = 72
    private let answerAnchorID = "review-answer"
    private static let revealAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.88)

    private var usesFlipStyle: Bool {
        reviewSettings.cardRevealStyle == .flip
    }

    var body: some View {
        VStack(spacing: 0) {
            wordTitleBlock
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)

            if usesFlipStyle {
                flipCardBody
            } else {
                revealCardBody
            }
        }
        .animation(Self.revealAnimation, value: showBack)
        .onChange(of: content.word) { _, _ in
            collapseAllModules()
        }
    }

    private var revealCardBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if hasExamplePrompt {
                        promptSection
                            .frame(minHeight: showBack ? nil : 168, alignment: .topLeading)
                    }

                    if !showBack, content.cardType != .appreciation {
                        scrollHintRow {
                            revealAnswer(proxy: proxy)
                        }
                        .padding(.top, AppSpacing.sm)
                    } else if showBack {
                        Divider()
                            .overlay(AppColor.border.opacity(0.55))
                            .padding(.top, AppSpacing.xs)

                        answerSection(scrollProxy: proxy)
                            .id(answerAnchorID)
                    }

                    Color.clear.frame(height: AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.md)
                .textSelection(.enabled)
            }
            .simultaneousGesture(revealAndRateGesture(proxy: proxy))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset.width * 0.18)
    }

    private var flipCardBody: some View {
        VStack(spacing: 0) {
            ZStack {
                flipFacePanel {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if hasExamplePrompt {
                            promptSection
                        }
                        Text(L10n.tapToReveal)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, AppSpacing.sm)
                    }
                }
                .opacity(showBack ? 0 : 1)
                .rotation3DEffect(.degrees(showBack ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .allowsHitTesting(!showBack)
                .onTapGesture { flipCard(toBack: true) }

                flipFacePanel {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if hasExamplePrompt {
                            promptSection
                            Divider().overlay(AppColor.border.opacity(0.7))
                        }
                        answerSection(scrollProxy: nil)
                    }
                }
                .opacity(showBack ? 1 : 0)
                .rotation3DEffect(.degrees(showBack ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .allowsHitTesting(showBack)
                .onTapGesture { flipCard(toBack: false) }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: dragOffset.width * 0.18)
            .simultaneousGesture(flipRateGesture)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(showBack ? L10n.backLabel : L10n.frontLabel)
            .accessibilityHint(showBack ? L10n.tapToFlipBack : L10n.tapToReveal)

            if !showBack {
                Button {
                    flipCard(toBack: true)
                } label: {
                    Label(L10n.showAnswer, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(RevealAnswerButtonStyle())
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }
        }
    }

    private func flipFacePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .lineSpacing(6)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(AppSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        )
    }

    private var wordTitleBlock: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                if showBack || content.cardType == .definition || content.cardType == .appreciation {
                    if content.cardType == .appreciation {
                        Text(content.word)
                            .font(AppFont.sectionTitle())
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.cardTypeAppreciation)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textTertiary)
                    } else {
                        Text(content.word)
                            .font(AppFont.studyWord())
                            .foregroundStyle(AppColor.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .move(edge: .leading)))

                        if let phonetic = content.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !phonetic.isEmpty {
                            Text(phonetic.hasPrefix("/") || phonetic.hasPrefix("[") ? phonetic : "/\(phonetic)/")
                                .font(AppFont.secondary())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                } else {
                    Text(L10n.cardTypeCloze)
                        .font(AppFont.caption().weight(.medium))
                        .foregroundStyle(AppColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                if showBack {
                    compactCollapseButton
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                speakButton
                    .padding(.top, 2)
                    .opacity(showBack || content.cardType == .definition || content.cardType == .appreciation ? 1 : 0)
                    .allowsHitTesting(showBack || content.cardType == .definition || content.cardType == .appreciation)
            }
        }
        .animation(Self.revealAnimation, value: showBack)
    }

    private var anyModuleExpanded: Bool {
        relatedWordsExpanded || aiExpanded || paraphrasesExpanded
    }

    private var compactCollapseButton: some View {
        Button {
            withAnimation(Self.revealAnimation) {
                if anyModuleExpanded {
                    collapseAllModules()
                } else {
                    showBack = false
                }
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(AppColor.textSecondary)
                .background(AppColor.surfaceMuted, in: Circle())
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(
            anyModuleExpanded ? L10n.reviewCollapseModules : L10n.reviewCollapseAnswer
        )
    }

    private var speakButton: some View {
        Button {
            let text = content.cardType == .appreciation ? content.sentence : content.word
            SpeechService.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(AppColor.accent)
                .background(AppColor.accentBackground(0.14), in: Circle())
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(L10n.speakWord)
    }

    private var hasExamplePrompt: Bool {
        CardContentFormatter.hasExamplePrompt(sentence: content.sentence, word: content.word)
    }

    private var promptSection: some View {
        let literaryFont: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .body)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: 18)
            }
            return base.withSize(18)
        }()

        return SelectableStudyText(
            text: content.displayFront,
            highlightTerms: content.cardType == .appreciation
                ? []
                : (content.cardType == .definition || showBack ? [content.displayHighlight] : []),
            matchStyle: .wordBounded,
            font: literaryFont,
            onLookup: { _ in },
            onSetHighlight: { term in
                onHighlight?(term)
            },
            onCreateCard: { term in
                onCreateCard?(term)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(L10n.frontLabel)
    }

    private func scrollHintRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                Text(L10n.reviewScrollForAnswer)
                    .font(AppFont.helper())
            }
            .foregroundStyle(AppColor.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
            .opacity(hasSeenScrollHint ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.reviewScrollForAnswer)
    }

    @ViewBuilder
    private func answerSection(scrollProxy: ScrollViewProxy?) -> some View {
        if content.cardType == .appreciation {
            appreciationAnswer(scrollProxy: scrollProxy)
        } else {
            vocabularyAnswer(scrollProxy: scrollProxy)
        }
    }

    @ViewBuilder
    private func appreciationAnswer(scrollProxy: ScrollViewProxy?) -> some View {
        let theme = CardContentFormatter.senseText(content.back)
        let showTheme = !CardContentFormatter.isPlaceholderAppreciationTheme(
            theme,
            localizedTypeName: L10n.cardTypeAppreciation
        )
        let translation = CardContentFormatter.sentenceTranslation(content.contextNote)
        let appreciation = content.usageNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = content.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isEmpty = CardContentFormatter.isHollowAppreciation(
            theme: theme,
            translation: content.contextNote,
            appreciation: content.usageNote
        )

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if isEmpty {
                Text(L10n.reviewAppreciationEmpty)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppSpacing.xs)
            } else {
                if showTheme {
                    module(title: L10n.reviewAppreciationThemeSection, titleStrong: true) {
                        Text(theme)
                            .font(AppFont.body().weight(.medium))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                }
                if let translation, !translation.isEmpty {
                    module(title: L10n.reviewTranslationSection, titleStrong: true) {
                        Text(translation)
                            .font(AppFont.body())
                            .foregroundStyle(AppColor.textBody)
                    }
                }
                if !appreciation.isEmpty {
                    module(title: L10n.reviewAppreciationSection, titleStrong: true) {
                        Text(appreciation)
                            .font(AppFont.secondary())
                            .foregroundStyle(AppColor.textBody)
                    }
                }
            }
            sourceBlock(source: source, imagePath: content.sourceImagePath)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.backLabel)
    }

    @ViewBuilder
    private func vocabularyAnswer(scrollProxy: ScrollViewProxy?) -> some View {
        let sense = CardContentFormatter.senseText(content.back)
        let translation = CardContentFormatter.sentenceTranslation(content.contextNote)
        let highlightTerms = CardContentFormatter.translationHighlightTerms(
            contextNote: content.contextNote,
            sense: sense
        )
        let usage = content.usageNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let etymology = content.etymology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let synonymList = Array(CardContentFormatter.splitRelatedWords(content.synonyms).prefix(3))
        let antonymList = Array(CardContentFormatter.splitRelatedWords(content.antonyms).prefix(2))
        let paraphrases = Array(CardContentFormatter.decodeParaphrases(content.paraphrases).prefix(2))
        let source = content.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasExtension =
            !synonymList.isEmpty || !antonymList.isEmpty || !usage.isEmpty || !paraphrases.isEmpty

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if !sense.isEmpty {
                    module(title: L10n.reviewMeaningSection, titleStrong: true) {
                        Text(sense)
                            .font(AppFont.body().weight(.medium))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                } else if translation == nil || translation?.isEmpty == true {
                    Text(content.localizedDisplayBack)
                        .font(AppFont.body())
                        .foregroundStyle(AppColor.textPrimary)
                }

                if let translation, !translation.isEmpty {
                    module(title: L10n.reviewTranslationSection, titleStrong: true) {
                        HighlightedText(
                            text: translation,
                            terms: highlightTerms,
                            font: AppFont.body(),
                            emphasizeForeground: true
                        )
                        .foregroundStyle(AppColor.textBody)
                    }
                }

                if !etymology.isEmpty {
                    module(title: L10n.cardEtymologyLabel) {
                        Text(etymology)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                sourceBlock(source: source, imagePath: content.sourceImagePath)
            }

            if hasExtension {
                Divider()
                    .overlay(AppColor.border.opacity(0.55))

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if !synonymList.isEmpty || !antonymList.isEmpty {
                        disclosure(
                            title: L10n.reviewRelatedWordsSection,
                            anchorID: "review-module-related",
                            isExpanded: $relatedWordsExpanded,
                            scrollProxy: scrollProxy
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                if !synonymList.isEmpty {
                                    relatedRow(label: L10n.cardSynonymsLabel, value: synonymList.joined(separator: " · "))
                                }
                                if !antonymList.isEmpty {
                                    relatedRow(label: L10n.cardAntonymsLabel, value: antonymList.joined(separator: " · "))
                                }
                            }
                        }
                    }

                    if !usage.isEmpty {
                        disclosure(
                            title: L10n.reviewAIInsightSection,
                            anchorID: "review-module-ai",
                            isExpanded: $aiExpanded,
                            scrollProxy: scrollProxy
                        ) {
                            Text(usage)
                                .font(AppFont.secondary())
                                .foregroundStyle(AppColor.textBody)
                        }
                    }

                    if !paraphrases.isEmpty {
                        disclosure(
                            title: L10n.reviewParaphrasesSection,
                            anchorID: "review-module-paraphrases",
                            isExpanded: $paraphrasesExpanded,
                            scrollProxy: scrollProxy
                        ) {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                ForEach(paraphrases) { item in
                                    paraphraseBlock(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.backLabel)
    }

    @ViewBuilder
    private func sourceBlock(source: String, imagePath: String?) -> some View {
        if !source.isEmpty || imagePath != nil {
            VStack(alignment: .leading, spacing: 4) {
                if !source.isEmpty {
                    Text(L10n.cardSource(source))
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textTertiary)
                }
                CardSourceImageThumbnail(relativePath: imagePath, maxHeight: 88)
            }
        }
    }

    private func disclosure<Content: View>(
        title: String,
        anchorID: String,
        isExpanded: Binding<Bool>,
        scrollProxy: ScrollViewProxy?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(AppFont.secondary().weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .tint(AppColor.textSecondary)
        .id(anchorID)
        .onChange(of: isExpanded.wrappedValue) { _, expanded in
            guard expanded else { return }
            guard let scrollProxy else { return }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.28)) {
                    scrollProxy.scrollTo(anchorID, anchor: .top)
                }
            }
        }
    }

    private func collapseAllModules() {
        relatedWordsExpanded = false
        aiExpanded = false
        paraphrasesExpanded = false
    }

    private func relatedRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.weak().weight(.medium))
                .foregroundStyle(AppColor.textTertiary)
            Text(value)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textBody)
        }
    }

    private func paraphraseBlock(_ item: CardParaphrase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.scene.isEmpty {
                Text(item.scene)
                    .font(AppFont.weak().weight(.medium))
                    .foregroundStyle(AppColor.textTertiary)
            }
            Text(item.sentence)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textBody)
            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private func module<Content: View>(
        title: String,
        titleStrong: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(titleStrong ? AppFont.secondary().weight(.bold) : AppFont.caption().weight(.semibold))
                .foregroundStyle(titleStrong ? AppColor.textSecondary : AppColor.textTertiary)
            content()
        }
    }

    private func revealAnswer(proxy: ScrollViewProxy? = nil) {
        hasSeenScrollHint = true
        withAnimation(Self.revealAnimation) {
            showBack = true
        }
        onRevealed?()
        if let proxy {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(answerAnchorID, anchor: .top)
                }
            }
        }
    }

    private func flipCard(toBack: Bool? = nil) {
        withAnimation(Self.revealAnimation) {
            if let toBack {
                showBack = toBack
            } else {
                showBack.toggle()
            }
        }
        if showBack {
            onRevealed?()
        }
    }

    private func revealAndRateGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard allowsReviewGestures, showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) + 12 else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer { dragOffset = .zero }
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if !showBack, vertical > 56, abs(vertical) > abs(horizontal) {
                    revealAnswer(proxy: proxy)
                    return
                }

                guard allowsReviewGestures, showBack else { return }
                guard abs(horizontal) > abs(vertical) + 8 else { return }

                if horizontal <= -swipeThreshold {
                    onSwipeAgain?()
                } else if horizontal >= swipeThreshold {
                    onSwipeEasy?()
                }
            }
    }

    private var flipRateGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard allowsReviewGestures, showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) + 12 else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer { dragOffset = .zero }
                guard allowsReviewGestures, showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width <= -swipeThreshold {
                    onSwipeAgain?()
                } else if value.translation.width >= swipeThreshold {
                    onSwipeEasy?()
                }
            }
    }
}
