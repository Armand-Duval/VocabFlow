import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FlashCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shareImport: ShareImportCoordinator

    @Bindable var card: FlashCard

    @State private var showEditSheet = false
    @State private var showMoreActions = false
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false
    @State private var showRegenerateConfirm = false
    @State private var isRegenerating = false
    @State private var apkgDocument: ApkgDocument?
    @State private var showApkgExporter = false
    @State private var apkgExportFilename = ApkgExportService.defaultFilename
    @State private var contentRevision = 0

    var body: some View {
        detailContent
            .id(contentRevision)
            .navigationTitle(card.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(L10n.libraryEdit) { showEditSheet = true }
                    Button {
                        showMoreActions = true
                    } label: {
                        AppIcon.symbol("ellipsis.circle")
                    }
                    .accessibilityLabel(L10n.libraryEdit)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                FlashCardEditSheet(card: card) {
                    contentRevision &+= 1
                }
            }
            .appActionSheet(isPresented: $showMoreActions, actions: moreActions)
            .appConfirmSheet(
                isPresented: $showRegenerateConfirm,
                title: L10n.cardRegenerate,
                message: L10n.cardRegenerateMessage,
                confirmTitle: L10n.cardRegenerate,
                confirmRole: .accent
            ) {
                Task { await regenerateCard() }
            }
            .appConfirmSheet(
                isPresented: $showDeleteConfirm,
                title: L10n.libraryDeleteCard,
                message: L10n.libraryDeleteCardMessage,
                confirmTitle: L10n.libraryDeleteCard,
                confirmRole: .destructive
            ) {
                modelContext.delete(card)
                DeckCardCountService.notifyDataMaintenance()
                dismiss()
            }
            .appConfirmSheet(
                isPresented: $showResetConfirm,
                title: L10n.libraryResetSRS,
                message: L10n.libraryResetSRSMessage,
                confirmTitle: L10n.libraryResetSRS,
                confirmRole: .accent
            ) {
                ReviewScheduler.resetProgress(for: card)
                DeckCardCountService.notifyCatalogChanged()
            }
            .loadingOverlay(isPresented: isRegenerating, message: L10n.cardRegenerateRunning)
            .fileExporter(
                isPresented: $showApkgExporter,
                document: apkgDocument,
                contentType: .apkg,
                defaultFilename: apkgExportFilename
            ) { _ in }
    }

    private var moreActions: [AppSheetAction] {
        [
            AppSheetAction(
                title: L10n.cardRegenerate,
                systemImage: "sparkles",
                role: .accent,
                isEnabled: APISettings.canUseAI && !isRegenerating
            ) {
                showRegenerateConfirm = true
            },
            AppSheetAction(title: L10n.cardExportApkg, systemImage: "square.and.arrow.up") {
                exportCardApkg()
            },
            AppSheetAction(
                title: card.isSuspended ? L10n.cardUnsuspend : L10n.cardSuspend,
                systemImage: card.isSuspended ? "play.circle" : "pause.circle"
            ) {
                toggleSuspended()
            },
            AppSheetAction(
                title: L10n.libraryResetSRS,
                systemImage: "arrow.counterclockwise",
                isEnabled: !card.isSuspended
            ) {
                showResetConfirm = true
            },
            AppSheetAction(
                title: L10n.libraryDeleteCard,
                systemImage: "trash",
                role: .destructive
            ) {
                showDeleteConfirm = true
            }
        ]
    }

    private var detailContent: some View {
        List {
            if !card.isSuspended {
                Section {
                    NavigationLink {
                        CardReviewSessionView(cards: [card], dismissWhenComplete: true)
                    } label: {
                        Label(L10n.libraryReviewThisCard, systemImage: "brain.head.profile")
                    }
                }
            } else {
                Section {
                    Text(L10n.cardSuspendedHint)
                        .font(AppFont.secondary())
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.libraryDetailContent) {
                LabeledContent(L10n.deckTarget, value: card.deck?.name ?? L10n.deckDefaultName)
                LabeledContent(L10n.wordLabel, value: card.word)
                if let phonetic = card.phonetic, !phonetic.isEmpty {
                    LabeledContent(L10n.phoneticLabel, value: phonetic)
                }
                LabeledContent(L10n.typeLabel, value: card.cardType.displayName)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.sourceText)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                    SelectableStudyText(
                        text: card.sentence,
                        highlightTerms: [card.displayHighlight],
                        matchStyle: .wordBounded,
                        font: UIFont.preferredFont(forTextStyle: .body),
            onLookup: { _ in },
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
                    Text(L10n.studySelectionHint)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                }
                .padding(.vertical, 4)
                if let highlight = card.highlightText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !highlight.isEmpty,
                   highlight.caseInsensitiveCompare(card.word) != .orderedSame {
                    LabeledContent(L10n.studySelectionSetHighlight, value: highlight)
                }
                if let source = card.sourceAttribution, !source.isEmpty {
                    DetailField(label: L10n.cardSourceLabel, value: source)
                }
                if card.sourceImagePath != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.cardSourceImageLabel)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                        CardSourceImageThumbnail(relativePath: card.sourceImagePath, maxHeight: 200)
                    }
                    .padding(.vertical, 4)
                }
                DetailField(label: L10n.frontLabel, value: card.front)
                DetailField(label: L10n.backLabel, value: card.displayBack)
                if let usage = card.usageNote, !usage.isEmpty {
                    DetailField(label: L10n.cardUsageNoteLabel, value: usage)
                }
                if let etymology = card.etymology, !etymology.isEmpty {
                    DetailField(label: L10n.cardEtymologyLabel, value: etymology)
                }
                if let synonyms = card.synonyms, !synonyms.isEmpty {
                    DetailField(label: L10n.cardSynonymsLabel, value: synonyms)
                }
                if let antonyms = card.antonyms, !antonyms.isEmpty {
                    DetailField(label: L10n.cardAntonymsLabel, value: antonyms)
                }
                if let paraphrases = card.paraphrases, !paraphrases.isEmpty {
                    DetailField(label: L10n.cardParaphrasesLabel, value: paraphrases)
                }
            }

            Section(L10n.libraryDetailSRS) {
                LabeledContent(L10n.librarySRSStatus) {
                    srsStatusChip
                }
                if !card.isSuspended {
                    LabeledContent(L10n.librarySRSNextReview) {
                        Text(card.nextReviewDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                LabeledContent(L10n.librarySRSReviewCount, value: "\(card.reviewCount)")
                LabeledContent(L10n.librarySRSInterval, value: intervalText)
                LabeledContent(L10n.librarySRSEase, value: String(format: "%.2f", card.easeFactor))
            }
        }
    }

    private var srsStatusChip: some View {
        Group {
            if card.isSuspended {
                StatusChip(text: L10n.cardSuspendedStatus, style: .suspended)
            } else if card.isNewCard {
                StatusChip(text: L10n.librarySRSNew, style: .new)
            } else if ReviewScheduler.isDue(card) {
                StatusChip(text: L10n.dueForReview, style: .due)
            } else {
                StatusChip(text: L10n.librarySRSScheduled, style: .scheduled)
            }
        }
    }

    private var intervalText: String {
        if card.intervalDays <= 0 {
            "—"
        } else {
            L10n.intervalDays(Int(card.intervalDays.rounded()))
        }
    }

    private func toggleSuspended() {
        card.isSuspended.toggle()
        DeckCardCountService.notifyCatalogChanged()
        ToastCenter.shared.show(card.isSuspended ? L10n.cardSuspendedDone : L10n.cardUnsuspendedDone)
    }

    private func exportCardApkg() {
        do {
            let data = try ApkgExportService.export(cards: [card], deckName: card.deck?.name)
            apkgDocument = ApkgDocument(data: data)
            apkgExportFilename = ApkgExportService.sanitizedFilename(card.word)
            showApkgExporter = true
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    @MainActor
    private func regenerateCard() async {
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
}
