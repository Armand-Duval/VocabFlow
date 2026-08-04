import SwiftUI
import SwiftData

/// Editable field bag shared by the review/edit sheet (and detail if needed).
struct FlashCardEditFields: Equatable {
    var word = ""
    var phonetic = ""
    var sentence = ""
    var cardType: CardType = .definition
    var front = ""
    var back = ""
    /// Sentence translation without 【】 markers.
    var translationPlain = ""
    /// Short gloss to highlight inside the translation.
    var translationHighlight = ""
    var usageNote = ""
    var etymology = ""
    var sourceAttribution = ""
    var deckID = UUID()

    var composedContextNote: String {
        CardContentFormatter.applyHighlightMarker(to: translationPlain, term: translationHighlight)
    }

    var highlightMissing: Bool {
        let term = translationHighlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return !CardContentFormatter.stripHighlightMarkers(translationPlain).contains(term)
    }

    static func load(from card: FlashCard, defaultDeckID: UUID) -> FlashCardEditFields {
        let note = card.contextNote ?? ""
        return FlashCardEditFields(
            word: card.word,
            phonetic: card.phonetic ?? "",
            sentence: card.sentence,
            cardType: card.cardType,
            front: card.front,
            back: card.back,
            translationPlain: CardContentFormatter.stripHighlightMarkers(note),
            translationHighlight: CardContentFormatter.primaryHighlightTerm(from: note),
            usageNote: card.usageNote ?? "",
            etymology: card.etymology ?? "",
            sourceAttribution: card.sourceAttribution ?? "",
            deckID: card.deck?.id ?? defaultDeckID
        )
    }

    @MainActor
    func apply(to card: FlashCard, in modelContext: ModelContext) {
        card.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let phonetic = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        card.phonetic = phonetic.isEmpty ? nil : phonetic
        card.sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        card.cardType = cardType
        card.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        card.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = composedContextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        card.contextNote = note.isEmpty ? nil : note
        let usage = usageNote.trimmingCharacters(in: .whitespacesAndNewlines)
        card.usageNote = usage.isEmpty ? nil : usage
        let roots = etymology.trimmingCharacters(in: .whitespacesAndNewlines)
        card.etymology = roots.isEmpty ? nil : roots
        let source = sourceAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
        card.sourceAttribution = source.isEmpty ? nil : source
        card.deck = DeckService.resolvedDeck(id: deckID, in: modelContext)
    }

    mutating func applyDraft(_ draft: GeneratedCardDraft) {
        let w = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !w.isEmpty { word = w }
        let s = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { sentence = s }
        cardType = draft.cardType
        front = CardContentFormatter.normalizedFront(
            front: draft.front,
            sentence: sentence,
            word: word,
            cardType: cardType
        )
        back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.contextNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        translationPlain = CardContentFormatter.stripHighlightMarkers(note)
        translationHighlight = CardContentFormatter.primaryHighlightTerm(from: note)
        if let phonetic = draft.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phonetic.isEmpty {
            self.phonetic = phonetic
        }
        if let usage = draft.usageNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !usage.isEmpty {
            usageNote = usage
        }
        if let etymology = draft.etymology?.trimmingCharacters(in: .whitespacesAndNewlines),
           !etymology.isEmpty {
            self.etymology = etymology
        }
        if let source = draft.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty {
            sourceAttribution = source
        }
    }
}

struct FlashCardEditorForm: View {
    @Binding var fields: FlashCardEditFields
    let decks: [Deck]
    var cardSourceImagePath: String? = nil

    var body: some View {
        Form {
            Section {
                labeledPicker(L10n.deckTarget) {
                    Picker(L10n.deckTarget, selection: $fields.deckID) {
                        ForEach(decks) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    }
                    .labelsHidden()
                }

                labeledField(L10n.wordLabel, text: $fields.word)
                labeledField(L10n.phoneticLabel, text: $fields.phonetic, prompt: L10n.phoneticPlaceholder)

                labeledPicker(L10n.typeLabel) {
                    Picker(L10n.typeLabel, selection: $fields.cardType) {
                        ForEach(CardType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                labeledField(L10n.cardSourceLabel, text: $fields.sourceAttribution, prompt: L10n.cardSourceLabel)

                if let path = cardSourceImagePath {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.cardSourceImageLabel)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                        CardSourceImageThumbnail(relativePath: path, maxHeight: 160)
                    }
                }
            } header: {
                Text(L10n.libraryEditBasics)
            }

            Section {
                labeledField(
                    L10n.sourceText,
                    text: $fields.sentence,
                    axis: .vertical,
                    lineLimit: 3...8
                )
                labeledField(
                    L10n.frontLabel,
                    text: $fields.front,
                    axis: .vertical,
                    lineLimit: 3...10
                )
            } header: {
                Text(L10n.libraryEditFrontSection)
            } footer: {
                Text(L10n.libraryEditFrontFooter)
            }

            Section {
                labeledField(
                    L10n.backLabel,
                    text: $fields.back,
                    axis: .vertical,
                    lineLimit: 3...10,
                    prompt: L10n.backPlaceholder
                )
                labeledField(
                    L10n.cardUsageNoteLabel,
                    text: $fields.usageNote,
                    axis: .vertical,
                    lineLimit: 2...8,
                    prompt: L10n.cardUsageNotePlaceholder
                )
                labeledField(
                    L10n.cardEtymologyLabel,
                    text: $fields.etymology,
                    axis: .vertical,
                    lineLimit: 1...4,
                    prompt: L10n.cardEtymologyPlaceholder
                )
                labeledField(
                    L10n.cardSentenceTranslation,
                    text: $fields.translationPlain,
                    axis: .vertical,
                    lineLimit: 2...8
                )
                labeledField(
                    L10n.cardTranslationHighlight,
                    text: $fields.translationHighlight
                )
                .textInputAutocapitalization(.never)

                if fields.highlightMissing {
                    Text(L10n.cardTranslationHighlightMissing)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.danger)
                }

                if !fields.translationPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.cardTranslationHighlightPreview)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textSecondary)
                        HighlightedText(
                            text: CardContentFormatter.stripHighlightMarkers(fields.translationPlain),
                            terms: {
                                let term = fields.translationHighlight
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return term.isEmpty ? [] : [term]
                            }(),
                            font: AppFont.secondary(),
                            emphasizeForeground: true
                        )
                        .foregroundStyle(AppColor.textBody)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(L10n.libraryEditBackSection)
            } footer: {
                Text(L10n.libraryEditBackFooter)
            }
        }
        .dismissKeyboardOnScroll()
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil,
        prompt: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.caption().weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
            if axis == .vertical {
                TextField(prompt ?? title, text: text, axis: .vertical)
                    .lineLimit(lineLimit ?? 2...6)
            } else {
                TextField(prompt ?? title, text: text)
            }
        }
        .padding(.vertical, 2)
    }

    private func labeledPicker<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.caption().weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// Manual edit + optional AI regenerate (fills the form; user confirms with Done).
struct FlashCardEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let card: FlashCard
    var onSaved: (() -> Void)? = nil

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @State private var fields = FlashCardEditFields()
    @State private var isRegenerating = false
    @State private var showRegenerateConfirm = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            FlashCardEditorForm(
                fields: $fields,
                decks: decks,
                cardSourceImagePath: card.sourceImagePath
            )
                .navigationTitle(editNavigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.done) { save() }
                            .fontWeight(.semibold)
                            .disabled(isRegenerating)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showRegenerateConfirm = true
                        } label: {
                            Label(L10n.cardRegenerate, systemImage: "sparkles")
                        }
                        .disabled(isRegenerating || !APISettings.canUseAI)
                    }
                }
                .appConfirmSheet(
                    isPresented: $showRegenerateConfirm,
                    title: L10n.cardRegenerate,
                    message: L10n.cardRegenerateEditMessage,
                    confirmTitle: L10n.cardRegenerate,
                    confirmRole: .accent
                ) {
                    Task { await regenerateIntoForm() }
                }
                .loadingOverlay(isPresented: isRegenerating, message: L10n.cardRegenerateRunning)
                .onAppear {
                    guard !didLoad else { return }
                    didLoad = true
                    let defaultDeckID = DeckService.fetchOrCreateDefault(in: modelContext).id
                    fields = .load(from: card, defaultDeckID: defaultDeckID)
                }
        }
    }

    private var editNavigationTitle: String {
        let word = fields.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if word.isEmpty {
            return L10n.libraryEdit
        }
        return L10n.libraryEditTitle(word)
    }

    private func save() {
        fields.apply(to: card, in: modelContext)
        DeckCardCountService.notifyCatalogChanged()
        onSaved?()
        dismiss()
    }

    @MainActor
    private func regenerateIntoForm() async {
        isRegenerating = true
        defer { isRegenerating = false }

        // Temporarily mirror form → card content for the generator input, without saving deck/SRS side effects.
        let sentence = fields.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = fields.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !word.isEmpty else {
            ToastCenter.shared.show(L10n.cardRegenerateNoMatch)
            return
        }

        do {
            let drafts = try await KimiCardGenerator.generate(
                sentence: sentence,
                words: [word],
                sourceHint: {
                    let hint = fields.sourceAttribution.trimmingCharacters(in: .whitespacesAndNewlines)
                    return hint.isEmpty ? nil : hint
                }(),
                deckName: decks.first(where: { $0.id == fields.deckID })?.name
            )
            guard let draft = CardContentRegenerator.matchingDraft(
                in: drafts,
                word: word,
                cardType: fields.cardType
            ) else {
                ToastCenter.shared.show(L10n.cardRegenerateNoMatch)
                return
            }
            fields.applyDraft(draft)
            ToastCenter.shared.show(L10n.cardRegenerateDone)
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}
