import SwiftUI
import SwiftData

struct FlashCardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var card: FlashCard

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false

    @State private var editWord = ""
    @State private var editPhonetic = ""
    @State private var editSentence = ""
    @State private var editCardType: CardType = .definition
    @State private var editFront = ""
    @State private var editBack = ""
    @State private var editContextNote = ""
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
                            showResetConfirm = true
                        } label: {
                            Label(L10n.libraryResetSRS, systemImage: "arrow.counterclockwise")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(L10n.libraryDeleteCard, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(L10n.libraryDeleteCard, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L10n.libraryDeleteCard, role: .destructive) {
                modelContext.delete(card)
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.libraryDeleteCardMessage)
        }
        .confirmationDialog(L10n.libraryResetSRS, isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button(L10n.libraryResetSRS) {
                ReviewScheduler.resetProgress(for: card)
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.libraryResetSRSMessage)
        }
    }

    private var detailContent: some View {
        List {
            Section {
                NavigationLink {
                    CardReviewSessionView(cards: [card], dismissWhenComplete: true)
                } label: {
                    Label(L10n.libraryReviewThisCard, systemImage: "brain.head.profile")
                }
            }

            Section(L10n.libraryDetailContent) {
                LabeledContent(L10n.deckTarget, value: card.deck?.name ?? L10n.deckDefaultName)
                LabeledContent(L10n.wordLabel, value: card.word)
                if let phonetic = card.phonetic, !phonetic.isEmpty {
                    LabeledContent(L10n.phoneticLabel, value: phonetic)
                }
                LabeledContent(L10n.typeLabel, value: card.cardType.displayName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.sentence)
                        .font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.frontLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.front)
                        .font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.backLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.displayBack)
                        .font(.subheadline)
                }
            }

            Section(L10n.libraryDetailSRS) {
                LabeledContent(L10n.librarySRSStatus) {
                    Text(srsStatusText)
                        .foregroundStyle(ReviewScheduler.isDue(card) ? .orange : .secondary)
                }
                LabeledContent(L10n.librarySRSNextReview) {
                    Text(card.nextReviewDate.formatted(date: .abbreviated, time: .shortened))
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
            }
        }
        .dismissKeyboardOnScroll()
    }

    private var srsStatusText: String {
        if card.isNewCard {
            L10n.librarySRSNew
        } else if ReviewScheduler.isDue(card) {
            L10n.dueForReview
        } else {
            L10n.librarySRSScheduled
        }
    }

    private var intervalText: String {
        if card.intervalDays <= 0 {
            "—"
        } else {
            L10n.intervalDays(Int(card.intervalDays.rounded()))
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
        card.deck = DeckService.resolvedDeck(id: editDeckID, in: modelContext)
        isEditing = false
    }
}
