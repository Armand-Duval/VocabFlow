import SwiftUI
import SwiftData
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct CardReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReviewSettingsStore.self) private var reviewSettings
    @EnvironmentObject private var shareImport: ShareImportCoordinator

    let cards: [FlashCard]
    var dismissWhenComplete: Bool = false
    var showDeckName: Bool = false
    var onSessionComplete: (() -> Void)? = nil

    @State private var sessionQueue: [FlashCard] = []
    @State private var pendingLearning: [PendingLearningCard] = []
    @State private var currentIndex = 0
    @State private var showBack = false
    @State private var now = Date()
    @State private var dragOffset: CGSize = .zero
    @State private var editingCard: FlashCard?
    @State private var showCardActions = false
    @State private var showRegenerateConfirm = false
    @State private var isRegenerating = false
    @State private var aiExpanded = true
    /// Bumps when card content changes so the face re-renders without resetting the queue.
    @State private var contentRevision = 0

    @AppStorage("review.hasSeenScrollHint") private var hasSeenScrollHint = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let swipeThreshold: CGFloat = 72
    private let answerAnchorID = "review-answer"

    /// Library push uses dismiss; Review tab uses onSessionComplete — both get the same back chrome.
    private var canLeaveSession: Bool { dismissWhenComplete || onSessionComplete != nil }

    private var usesFlipStyle: Bool {
        reviewSettings.cardRevealStyle == .flip
    }

    var body: some View {
        Group {
            if let card = currentCard {
                reviewContent(for: card)
                    .id("\(card.id)-\(contentRevision)")
            } else if let nextLearningDate = pendingLearning.map(\.availableAt).min() {
                learningWaitState(nextAvailable: nextLearningDate)
            } else {
                sessionFinishedState
            }
        }
        // One shared study chrome: never use the system nav title (avoids Library showing the word as page title).
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(
            get: { editingCard != nil },
            set: { if !$0 { editingCard = nil } }
        )) {
            if let card = editingCard {
                FlashCardEditSheet(card: card) {
                    contentRevision &+= 1
                }
            }
        }
        .appActionSheet(
            isPresented: $showCardActions,
            actions: currentCardActions
        )
        .appConfirmSheet(
            isPresented: $showRegenerateConfirm,
            title: L10n.cardRegenerate,
            message: L10n.cardRegenerateMessage,
            confirmTitle: L10n.cardRegenerate,
            confirmRole: .accent
        ) {
            Task { await regenerateCurrentCard() }
        }
        .loadingOverlay(isPresented: isRegenerating, message: L10n.cardRegenerateRunning)
        .onAppear {
            syncSessionQueue(with: cards)
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            syncSessionQueue(with: cards)
        }
        .onReceive(timer) { date in
            now = date
            promoteReadyLearningCards()
        }
    }

    @ViewBuilder
    private var sessionFinishedState: some View {
        VStack(spacing: AppSpacing.md) {
            if canLeaveSession {
                sessionTopBar(trailing: EmptyView())
            }
            AppEmptyState(
                title: L10n.noCardsToReview,
                message: L10n.reviewEmptyDone,
                systemImage: "checkmark.circle",
                actionTitle: canLeaveSession ? (dismissWhenComplete ? L10n.done : L10n.reviewHomeBack) : nil,
                action: canLeaveSession ? { leaveSession() } : nil
            )
        }
    }

    private func leaveSession() {
        if dismissWhenComplete {
            dismiss()
        } else {
            onSessionComplete?()
        }
    }

    private var currentCard: FlashCard? {
        guard sessionQueue.indices.contains(currentIndex) else { return nil }
        return sessionQueue[currentIndex]
    }

    private func reviewContent(for card: FlashCard) -> some View {
        VStack(spacing: 0) {
            sessionTopBar(trailing: topTrailingActions(for: card))

            wordTitleBlock(for: card)
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)

            if showDeckName, let deckName = card.deck?.name, !deckName.isEmpty {
                Text(deckName)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xs)
            }

            if usesFlipStyle {
                flipCardBody(for: card)
            } else {
                revealCardBody(for: card)
            }
        }
        .animation(Self.revealAnimation, value: showBack)
    }

    private static let revealAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.88)

    private func revealCardBody(for card: FlashCard) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    promptSection(for: card)
                        .frame(minHeight: showBack ? nil : 168, alignment: .topLeading)

                    if !showBack {
                        scrollHintRow {
                            revealAnswer(proxy: proxy)
                        }
                        .padding(.top, AppSpacing.sm)
                    } else {
                        Divider()
                            .overlay(AppColor.border.opacity(0.7))
                            .padding(.vertical, AppSpacing.xs)

                        answerSection(for: card)
                            .id(answerAnchorID)
                    }

                    Color.clear.frame(height: AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.md)
                .textSelection(.enabled)
            }
            .simultaneousGesture(revealAndRateGesture(for: card, proxy: proxy))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showBack {
                    ratingButtons(for: card)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset.width * 0.18)
    }

    private func flipCardBody(for card: FlashCard) -> some View {
        VStack(spacing: 0) {
            ZStack {
                flipFacePanel {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        promptSection(for: card)
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

                flipFacePanel {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        // Complete back: keep the stem, then the full reveal content.
                        promptSection(for: card)
                        Divider().overlay(AppColor.border.opacity(0.7))
                        answerSection(for: card)
                    }
                }
                .opacity(showBack ? 1 : 0)
                .rotation3DEffect(.degrees(showBack ? 0 : -180), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                .allowsHitTesting(showBack)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: dragOffset.width * 0.18)
            .onTapGesture { flipCard() }
            .simultaneousGesture(flipRateGesture(for: card))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(showBack ? L10n.backLabel : L10n.frontLabel)

            if showBack {
                ratingButtons(for: card)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
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

    private func revealAnswer(proxy: ScrollViewProxy? = nil) {
        hasSeenScrollHint = true
        withAnimation(Self.revealAnimation) {
            showBack = true
        }
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
    }

    private func sessionTopBar<Trailing: View>(trailing: Trailing) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if canLeaveSession {
                Button {
                    leaveSession()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColor.surface, in: Circle())
                        .appSoftShadow()
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel(L10n.back)
            }

            Text(L10n.reviewProgress(currentIndex + 1, max(sessionQueue.count, 1)))
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    private func topTrailingActions(for card: FlashCard) -> some View {
        Button {
            showCardActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(AppColor.surface, in: Circle())
                .appSoftShadow()
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(L10n.libraryEdit)
    }

    private var currentCardActions: [AppSheetAction] {
        [
            AppSheetAction(title: L10n.libraryEdit, systemImage: "pencil") {
                editingCard = currentCard
            },
            AppSheetAction(
                title: L10n.cardRegenerate,
                systemImage: "sparkles",
                role: .accent,
                isEnabled: APISettings.canUseAI && !isRegenerating
            ) {
                showRegenerateConfirm = true
            }
        ]
    }

    @MainActor
    private func regenerateCurrentCard() async {
        guard let card = currentCard else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await CardContentRegenerator.regenerate(card)
            contentRevision &+= 1
            ToastCenter.shared.show(L10n.cardRegenerateDone)
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func wordTitleBlock(for card: FlashCard) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                if showBack || card.cardType == .definition {
                    Text(card.word)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    if let phonetic = card.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !phonetic.isEmpty {
                        Text(phonetic.hasPrefix("/") || phonetic.hasPrefix("[") ? phonetic : "/\(phonetic)/")
                            .font(AppFont.secondary())
                            .foregroundStyle(AppColor.textSecondary)
                    }
                } else {
                    Text(L10n.cardTypeCloze)
                        .font(AppFont.caption().weight(.medium))
                        .foregroundStyle(AppColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }

            speakButton(for: card)
                .padding(.top, 2)
                .opacity(showBack || card.cardType == .definition ? 1 : 0)
                .allowsHitTesting(showBack || card.cardType == .definition)
        }
        .animation(Self.revealAnimation, value: showBack)
    }

    private func speakButton(for card: FlashCard) -> some View {
        Button {
            SpeechService.speak(card.word)
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

    private func promptSection(for card: FlashCard) -> some View {
        let literaryFont: UIFont = {
            let base = UIFont.preferredFont(forTextStyle: .body)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: 18)
            }
            return base.withSize(18)
        }()

        return SelectableStudyText(
            text: card.displayFront,
            highlightTerms: card.cardType == .definition || showBack
                ? [card.displayHighlight]
                : [],
            matchStyle: .wordBounded,
            font: literaryFont,
            onLookup: { _ in
                // Lookup is presented from the text view responder chain inside SelectableStudyText.
            },
            onSetHighlight: { term in
                card.highlightText = term
                contentRevision &+= 1
                ToastCenter.shared.show(L10n.studySelectionHighlightUpdated)
            },
            onCreateCard: { term in
                shareImport.importPayload(
                    ShareImportPayload(
                        sentence: card.sentence,
                        selectedWord: term,
                        source: .clipboard
                    )
                )
                AppTab.request(.create)
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
    private func answerSection(for card: FlashCard) -> some View {
        let sense = CardContentFormatter.senseText(card.back)
        let translation = CardContentFormatter.sentenceTranslation(card.contextNote)
        let highlightTerms = CardContentFormatter.translationHighlightTerms(
            contextNote: card.contextNote,
            sense: sense
        )
        let usage = card.usageNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let etymology = card.etymology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasAI = !usage.isEmpty || !etymology.isEmpty
        let source = card.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if !sense.isEmpty {
                reviewModule(title: L10n.reviewMeaningSection, titleStrong: true) {
                    Text(sense)
                        .font(AppFont.body().weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                }
            }

            if let translation, !translation.isEmpty {
                reviewModule(title: L10n.reviewTranslationSection) {
                    HighlightedText(
                        text: translation,
                        terms: highlightTerms,
                        font: AppFont.body(),
                        emphasizeForeground: true
                    )
                    .foregroundStyle(AppColor.textBody)
                }
            }

            if hasAI {
                DisclosureGroup(isExpanded: $aiExpanded) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        if !usage.isEmpty {
                            Text(usage)
                                .font(AppFont.secondary())
                                .foregroundStyle(AppColor.textBody)
                        }
                        if !etymology.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.cardEtymologyLabel)
                                    .font(AppFont.weak().weight(.medium))
                                    .foregroundStyle(AppColor.textTertiary)
                                Text(etymology)
                                    .font(AppFont.secondary())
                                    .foregroundStyle(AppColor.textBody)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                } label: {
                    Text(L10n.reviewAIInsightSection)
                        .font(AppFont.caption().weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .tint(AppColor.textSecondary)
            }

            if sense.isEmpty, translation == nil || translation?.isEmpty == true {
                Text(card.displayBack)
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textPrimary)
            }

            if !source.isEmpty || card.sourceImagePath != nil {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    if !source.isEmpty {
                        Text(L10n.cardSource(source))
                            .font(AppFont.weak())
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    CardSourceImageThumbnail(relativePath: card.sourceImagePath, maxHeight: 120)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.backLabel)
    }

    private func reviewModule<Content: View>(
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

    private func revealAndRateGesture(for card: FlashCard, proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) + 12 else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer { dragOffset = .zero }

                let horizontal = value.translation.width
                let vertical = value.translation.height

                // 下滑展开答案；上滑收起（与「下滑查看释义」文案一致）
                if !showBack, vertical > 56, abs(vertical) > abs(horizontal) {
                    revealAnswer(proxy: proxy)
                    return
                }

                if showBack, vertical < -72, abs(vertical) > abs(horizontal) + 20 {
                    withAnimation(Self.revealAnimation) {
                        showBack = false
                    }
                    return
                }

                guard showBack else { return }
                guard abs(horizontal) > abs(vertical) else { return }

                if horizontal <= -swipeThreshold {
                    submit(rating: .again, for: card)
                } else if horizontal >= swipeThreshold {
                    submit(rating: .easy, for: card)
                }
            }
    }

    private func flipRateGesture(for card: FlashCard) -> some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                guard showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) + 12 else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                defer { dragOffset = .zero }
                guard showBack else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width <= -swipeThreshold {
                    submit(rating: .again, for: card)
                } else if value.translation.width >= swipeThreshold {
                    submit(rating: .easy, for: card)
                }
            }
    }

    private func learningWaitState(nextAvailable: Date) -> some View {
        VStack(spacing: AppSpacing.md) {
            if canLeaveSession {
                sessionTopBar(trailing: EmptyView())
            }
            AppEmptyState(
                title: L10n.reviewLearningWaitTitle,
                message: L10n.reviewLearningWaitMessage(ReviewScheduler.formatInterval(from: now, to: nextAvailable)),
                systemImage: "clock",
                actionTitle: canLeaveSession ? (dismissWhenComplete ? L10n.done : L10n.reviewHomeBack) : nil,
                action: canLeaveSession ? { leaveSession() } : nil
            )
        }
    }

    private func ratingButtons(for card: FlashCard) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(ReviewRating.userChoices, id: \.rawValue) { rating in
                Button {
                    submit(rating: rating, for: card)
                } label: {
                    HStack(spacing: 4) {
                        Text(rating.title)
                            .font(.subheadline.weight(.semibold))
                        Text(ReviewScheduler.intervalLabel(for: card, rating: rating, now: now))
                            .font(AppFont.weak())
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(ReviewRatingButtonStyle(rating: rating))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.sm)
        .background(AppColor.pageBackground.opacity(0.96))
    }

    private func submit(rating: ReviewRating, for card: FlashCard) {
        playRatingHaptic(rating)
        let preview = ReviewScheduler.preview(rating: rating, for: card, now: now)
        ReviewScheduler.apply(rating: rating, to: card, now: now)
        StudyStreakStore.recordStudy(now: now)
        NotificationCenter.default.post(name: .reviewQueueDidChange, object: nil)
        showBack = false
        dragOffset = .zero
        aiExpanded = true

        sessionQueue.removeAll { $0.id == card.id }

        if ReviewScheduler.isLearningDelay(preview, now: now) {
            pendingLearning.append(PendingLearningCard(card: card, availableAt: preview.nextReviewDate))
        }

        if sessionQueue.isEmpty {
            promoteReadyLearningCards()
        }

        if sessionQueue.isEmpty {
            if dismissWhenComplete, pendingLearning.isEmpty {
                dismiss()
            }
            return
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
    }

    private func playRatingHaptic(_ rating: ReviewRating) {
        #if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch rating {
        case .again, .hard:
            style = .medium
        case .good, .easy:
            style = .light
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    private func syncSessionQueue(with cards: [FlashCard]) {
        let pendingIDs = Set(pendingLearning.map(\.card.id))

        if sessionQueue.isEmpty {
            let initial = cards.filter { !pendingIDs.contains($0.id) }
            sessionQueue = ReviewQueueBuilder.shuffledAvoidingAdjacentSameWord(initial)
            currentIndex = 0
            return
        }

        let existingIDs = Set(sessionQueue.map(\.id))
        for card in cards where !pendingIDs.contains(card.id) && !existingIDs.contains(card.id) {
            insertAvoidingSameWord(card)
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
    }

    private func promoteReadyLearningCards() {
        let ready = pendingLearning.filter { $0.availableAt <= now }.map(\.card)
        guard !ready.isEmpty else { return }

        pendingLearning.removeAll { $0.availableAt <= now }
        for card in ReviewQueueBuilder.shuffledAvoidingAdjacentSameWord(ready) {
            insertAvoidingSameWord(card)
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
        showBack = false
    }

    /// Insert after the current card when possible, skipping spots that would put
    /// the same word or sentence back-to-back.
    private func insertAvoidingSameWord(_ card: FlashCard) {
        if sessionQueue.isEmpty {
            sessionQueue.append(card)
            return
        }

        let start = min(currentIndex + 1, sessionQueue.count)

        if let index = (start...sessionQueue.count).first(where: { insertionIndex in
            let beforeOK = insertionIndex == 0
                || !ReviewQueueBuilder.sharesStudyContext(sessionQueue[insertionIndex - 1], with: card)
            let afterOK = insertionIndex == sessionQueue.count
                || !ReviewQueueBuilder.sharesStudyContext(sessionQueue[insertionIndex], with: card)
            return beforeOK && afterOK
        }) {
            sessionQueue.insert(card, at: index)
        } else {
            sessionQueue.append(card)
        }
    }
}

private struct PendingLearningCard: Identifiable {
    let card: FlashCard
    let availableAt: Date

    var id: UUID { card.id }
}

private struct ReviewRatingButtonStyle: ButtonStyle {
    let rating: ReviewRating

    func makeBody(configuration: Configuration) -> some View {
        let palette = palette(for: rating)
        configuration.label
            .foregroundStyle(palette.foreground)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(palette.background.opacity(configuration.isPressed ? 1.12 : 1))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(palette.border.opacity(configuration.isPressed ? 0.8 : 0.9), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func palette(for rating: ReviewRating) -> (background: Color, border: Color, foreground: Color) {
        switch rating {
        case .again:
            (
                AppColor.ratingAgainBackground(),
                AppColor.danger.opacity(0.28),
                AppColor.danger
            )
        case .hard:
            (
                AppColor.ratingHardBackground(),
                AppColor.warning.opacity(0.32),
                AppColor.warning
            )
        case .good:
            (
                AppColor.surfaceMuted,
                AppColor.border,
                AppColor.accentStrong
            )
        case .easy:
            (
                AppColor.ratingEasyBackground(),
                AppColor.success.opacity(0.28),
                AppColor.success
            )
        }
    }
}

#Preview {
    NavigationStack {
        CardReviewSessionView(cards: [])
            .navigationTitle(L10n.studyTitle)
    }
    .environment(ReviewSettingsStore.shared)
    .environmentObject(ShareImportCoordinator())
    .modelContainer(for: FlashCard.self, inMemory: true)
}
