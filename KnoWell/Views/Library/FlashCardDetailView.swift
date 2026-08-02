import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FlashCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var card: FlashCard

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false
    @State private var apkgDocument: ApkgDocument?
    @State private var showApkgExporter = false
    @State private var apkgExportFilename = ApkgExportService.defaultFilename

    @State private var editWord = ""
    @State private var editPhonetic = ""
    @State private var editSentence = ""
    @State private var editCardType: CardType = .definition
    @State private var editFront = ""
    @State private var editBack = ""
    @State private var editContextNote = ""
    @State private var editSourceAttribution = ""
    @State private var editDeckID = UUID()

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                detailContent
            }
        }
        .navigationTitle(card.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isEditing {
                    Button(L10n.cancel) { cancelEditing() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button(L10n.done) { saveEdits() }
                        .fontWeight(.semibold)
                } else {
                    Button(L10n.libraryEdit) { beginEditing() }
                    Menu {
                        Button {
                            exportCardApkg()
                        } label: {
                            Label(L10n.cardExportApkg, systemImage: "square.and.arrow.up")
                        }

                        Button {
                            toggleSuspended()
                        } label: {
                            Label(
                                card.isSuspended ? L10n.cardUnsuspend : L10n.cardSuspend,
                                systemImage: card.isSuspended ? "play.circle" : "pause.circle"
                            )
                        }

                        Button {
                            showResetConfirm = true
                        } label: {
                            Label(L10n.libraryResetSRS, systemImage: "arrow.counterclockwise")
                        }
                        .disabled(card.isSuspended)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(L10n.libraryDeleteCard, systemImage: "trash")
                        }
                    } label: {
                        AppIcon.symbol("ellipsis.circle")
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showApkgExporter,
            document: apkgDocument,
            contentType: .apkg,
            defaultFilename: apkgExportFilename
        ) { _ in }
        .confirmationDialog(L10n.libraryDeleteCard, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.libraryDeleteCard, role: .destructive) {
                modelContext.delete(card)
                DeckCardCountService.notifyDataMaintenance()
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.libraryDeleteCardMessage)
        }
        .confirmationDialog(L10n.libraryResetSRS, isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button(L10n.libraryResetSRS) {
                ReviewScheduler.resetProgress(for: card)
                DeckCardCountService.notifyCatalogChanged()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.libraryResetSRSMessage)
        }
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
                DetailField(label: L10n.sourceText, value: card.sentence)
                if let source = card.sourceAttribution, !source.isEmpty {
                    DetailField(label: L10n.cardSourceLabel, value: source)
                }
                DetailField(label: L10n.frontLabel, value: card.front)
                DetailField(label: L10n.backLabel, value: card.displayBack)
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

    private var editForm: some View {
        Form {
            Section(L10n.libraryDetailContent) {
                Picker(L10n.deckTarget, selection: $editDeckID) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(deck.id)
                    }
                }
                TextField(L10n.wordLabel, text: $editWord)
                TextField(L10n.phoneticPlaceholder, text: $editPhonetic)
                Picker(L10n.typeLabel, selection: $editCardType) {
                    ForEach(CardType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField(L10n.sourceText, text: $editSentence, axis: .vertical)
                    .lineLimit(3...8)
                TextField(L10n.frontLabel, text: $editFront, axis: .vertical)
                    .lineLimit(3...10)
                TextField(L10n.backLabel, text: $editBack, axis: .vertical)
                    .lineLimit(3...10)
                TextField(L10n.libraryContextNote, text: $editContextNote, axis: .vertical)
                    .lineLimit(2...6)
                TextField(L10n.cardSourceLabel, text: $editSourceAttribution)
            }
        }
        .dismissKeyboardOnScroll()
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

    private func beginEditing() {
        editWord = card.word
        editPhonetic = card.phonetic ?? ""
        editSentence = card.sentence
        editCardType = card.cardType
        editFront = card.front
        editBack = card.back
        editContextNote = card.contextNote ?? ""
        editSourceAttribution = card.sourceAttribution ?? ""
        editDeckID = card.deck?.id ?? DeckService.fetchOrCreateDefault(in: modelContext).id
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
    }

    private func saveEdits() {
        card.word = editWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let phonetic = editPhonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        card.phonetic = phonetic.isEmpty ? nil : phonetic
        card.sentence = editSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        card.cardType = editCardType
        card.front = editFront.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = editBack.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = editContextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        card.contextNote = note.isEmpty ? nil : note
        let source = editSourceAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
        card.sourceAttribution = source.isEmpty ? nil : source
        card.deck = DeckService.resolvedDeck(id: editDeckID, in: modelContext)
        isEditing = false
        DeckCardCountService.notifyCatalogChanged()
    }
}
