import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct CardPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @Binding var selectedDeckID: UUID?
    @ObservedObject private var generationQueue = CardGenerationQueue.shared
    var onComplete: () -> Void

    @State private var drafts: [GeneratedCardDraft] = []
    @State private var cursor = 0
    @State private var showBack = false
    @State private var faceDragOffset: CGSize = .zero
    @State private var showReplaceReasons = false
    @State private var isReplacing = false
    @State private var phase: Phase = .triage
    @State private var savedCards: [FlashCard] = []
    @State private var skippedDuplicateCount = 0
    @State private var showReview = false
    @State private var didCommit = false

    private enum Phase {
        case triage
        case done
    }

    init(selectedDeckID: Binding<UUID?>, onComplete: @escaping () -> Void) {
        _selectedDeckID = selectedDeckID
        self.onComplete = onComplete
    }

    private var currentDraft: GeneratedCardDraft? {
        guard phase == .triage, drafts.indices.contains(cursor) else { return nil }
        return drafts[cursor]
    }

    private var laterBatchCount: Int {
        max(0, generationQueue.pendingTriageCardCount - drafts.count)
    }

    var body: some View {
        Group {
            if phase == .done {
                doneState
            } else if let draft = currentDraft {
                triageContent(for: draft)
            } else {
                doneState
            }
        }
        .appPageBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if phase == .triage {
                triageHeader
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .triage {
                triageFooter
            }
        }
        .appActionSheet(
            isPresented: $showReplaceReasons,
            title: L10n.createPreviewReplaceTitle,
            actions: CardReplaceReason.allCases.map { reason in
                AppSheetAction(title: reason.title) {
                    Task { await replaceCurrent(reason: reason) }
                }
            }
        )
        .loadingOverlay(isPresented: isReplacing, message: L10n.createPreviewReplacing)
        .fullScreenCover(isPresented: $showReview) {
            NavigationStack {
                CardReviewSessionView(cards: savedCards, dismissWhenComplete: true)
            }
            .environmentObject(shareImport)
            .environment(ReviewSettingsStore.shared)
        }
        .onChange(of: showReview) { _, isShowing in
            if !isShowing, !savedCards.isEmpty {
                onComplete()
            }
        }
        .onAppear(perform: loadCurrentBatch)
        .onDisappear {
            persistProgressIfNeeded()
        }
    }

    private var navigationTitle: String {
        if phase == .done {
            return L10n.createPreviewDoneTitle
        }
        guard !drafts.isEmpty else { return L10n.previewTitle }
        return L10n.createPreviewProgress(cursor + 1, drafts.count)
    }

    private var triageHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Button(action: goBackOrDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColor.surface, in: Circle())
                        .appSoftShadow()
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel(L10n.createPreviewLater)

                Text(navigationTitle)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
                    .monospacedDigit()

                if laterBatchCount > 0 {
                    Text(L10n.createPreviewMoreWaiting(laterBatchCount))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            CreateDeckPickerCard(selectedDeckID: $selectedDeckID)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
        .background(AppColor.pageBackground)
    }

    private func triageContent(for draft: GeneratedCardDraft) -> some View {
        CardStudyFaceView(
            content: draft.studyContent,
            showBack: $showBack,
            dragOffset: $faceDragOffset,
            allowsReviewGestures: false,
            onCreateCard: { term in
                shareImport.importPayload(
                    ShareImportPayload(
                        sentence: draft.sentence,
                        selectedWord: term,
                        source: .clipboard
                    )
                )
            }
        )
        .id(draft.id)
    }

    private var triageFooter: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            footerIconButton(
                systemImage: "xmark",
                label: L10n.createPreviewDrop,
                tint: AppColor.danger
            ) {
                dropCurrent()
            }

            Button(L10n.createPreviewKeep) { keepCurrent() }
                .buttonStyle(PrimaryButtonStyle(prominent: true))

            footerIconButton(
                systemImage: "arrow.triangle.2.circlepath",
                label: L10n.createPreviewReplace,
                tint: AppColor.textSecondary,
                disabled: isReplacing || !APISettings.canUseAI
            ) {
                showReplaceReasons = true
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
        .background(AppColor.pageBackground)
    }

    private func footerIconButton(
        systemImage: String,
        label: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(AppColor.surface, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    private var doneState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: 0)
            if savedCards.isEmpty {
                AppEmptyState(
                    title: L10n.createPreviewDoneEmpty,
                    message: skippedDuplicateCount > 0
                        ? L10n.saveAllDuplicatesMessage
                        : L10n.createPreviewTapHint,
                    systemImage: "rectangle.stack.badge.minus",
                    actionTitle: L10n.createPreviewDoneAction,
                    action: onComplete
                )
            } else {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: AppIcon.emptyStateSize, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColor.success.opacity(0.86))
                    Text(L10n.createPreviewDoneTitle)
                        .font(AppFont.sectionTitle())
                    Text(L10n.createGenerateSuccess(savedCards.count))
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textSecondary)
                }
                Button(L10n.createPreviewReviewNow(savedCards.count)) {
                    showReview = true
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
                .padding(.horizontal, AppSpacing.xl)
                Button(L10n.createPreviewDoneAction, action: onComplete)
                    .font(AppFont.secondary().weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
    }

    private func keepCurrent() {
        hapticLight()
        updateCurrent { $0.isSelected = true }
        advance()
    }

    private func dropCurrent() {
        hapticMedium()
        updateCurrent { $0.isSelected = false }
        advance()
    }

    private func replaceCurrent(reason: CardReplaceReason) async {
        guard drafts.indices.contains(cursor) else { return }
        isReplacing = true
        defer { isReplacing = false }
        do {
            let deckName = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext).name
            let next = try await CardDraftRegenerator.replace(
                drafts[cursor],
                reason: reason,
                deckName: deckName
            )
            drafts[cursor] = next
            persistFullProgress()
            showBack = false
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    private func updateCurrent(_ mutate: (inout GeneratedCardDraft) -> Void) {
        guard drafts.indices.contains(cursor) else { return }
        mutate(&drafts[cursor])
    }

    private func advance() {
        showBack = false
        if cursor + 1 < drafts.count {
            cursor += 1
            persistFullProgress()
        } else {
            finishCurrentBatch()
        }
    }

    private func goBackOrDismiss() {
        persistProgressIfNeeded()
        onComplete()
    }

    private func loadCurrentBatch() {
        guard let batch = generationQueue.readyPreview else {
            if phase == .triage, drafts.isEmpty {
                phase = .done
            }
            return
        }
        drafts = batch.drafts
        selectedDeckID = batch.deckID
        cursor = min(max(batch.cursor, 0), max(batch.drafts.count - 1, 0))
        showBack = false
        phase = .triage
        didCommit = false
    }

    private func persistFullProgress() {
        guard phase == .triage, !drafts.isEmpty else { return }
        generationQueue.replaceCurrentTriage(
            drafts: drafts,
            deckID: selectedDeckID,
            cursor: cursor
        )
    }

    private func persistRemainingFromCursor() {
        guard phase == .triage else { return }
        let remaining = drafts.indices.contains(cursor) ? Array(drafts[cursor...]) : []
        generationQueue.replaceCurrentTriage(drafts: remaining, deckID: selectedDeckID, cursor: 0)
    }

    private func persistProgressIfNeeded() {
        guard !didCommit, phase == .triage else { return }
        didCommit = true
        saveKeptBeforeCursor()
        persistRemainingFromCursor()
    }

    @discardableResult
    private func saveKeptBeforeCursor() -> [FlashCard] {
        guard cursor > 0 else { return [] }
        let kept = Array(drafts.prefix(cursor).filter(\.isSelected))
        return saveDrafts(kept)
    }

    @discardableResult
    private func saveDrafts(_ items: [GeneratedCardDraft]) -> [FlashCard] {
        guard !items.isEmpty else { return [] }
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        selectedDeckID = deck.id
        let result = FlashCardSaver.save(drafts: items, to: modelContext, deck: deck)
        skippedDuplicateCount += result.skippedDuplicateCount
        savedCards.append(contentsOf: result.savedCards)
        if result.skippedAll {
            ToastCenter.shared.show(L10n.saveAllDuplicatesMessage)
        } else if result.didSaveAny {
            NotificationCenter.default.post(name: .reviewQueueDidChange, object: nil)
        }
        return result.savedCards
    }

    private func finishCurrentBatch() {
        didCommit = true
        saveDrafts(drafts.filter(\.isSelected))
        generationQueue.finishCurrentTriage()
        if generationQueue.readyPreview != nil {
            loadCurrentBatch()
        } else {
            phase = .done
        }
    }

    private func hapticLight() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func hapticMedium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

#Preview {
    NavigationStack {
        CardPreviewView(selectedDeckID: .constant(nil)) {}
    }
    .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
    .environmentObject(ShareImportCoordinator())
    .environment(ReviewSettingsStore.shared)
}
