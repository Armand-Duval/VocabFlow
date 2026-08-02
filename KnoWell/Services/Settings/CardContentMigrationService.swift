import Foundation
import SwiftData

struct CardContentMigrationReport: Sendable {
    var scanned = 0
    var frontsUpdated = 0
    var backsSplit = 0
    var contentRefreshed = 0
    var phoneticsFilled = 0
    var sourcesFilled = 0
    var unchanged = 0
    var aiFailures = 0

    var summaryMessage: String {
        L10n.settingsMigrateCardsDoneMessage(
            frontsUpdated,
            backsSplit,
            phoneticsFilled,
            sourcesFilled,
            contentRefreshed,
            aiFailures
        )
    }
}

/// Upgrades existing cards by re-running the **same** `KimiCardGenerator` rules used for new cards,
/// then merging content fields via `CardContentSync`. SRS / deck / id are preserved.
///
/// When card format gains new fields: update generator + `GeneratedCardDraft` + `FlashCard` +
/// `CardContentSync.applyGeneratedContent` — this button needs no special-case logic.
enum CardContentMigrationService {
    private static let localMigrationKey = "knowell.cardContent.localMigration.v1"
    private static let wordsPerGenerateCall = 4

    @MainActor
    @discardableResult
    static func migrateLocallyIfNeeded(in context: ModelContext) -> CardContentMigrationReport {
        guard !UserDefaults.standard.bool(forKey: localMigrationKey) else {
            return CardContentMigrationReport()
        }
        let report = migrateLocally(in: context)
        UserDefaults.standard.set(true, forKey: localMigrationKey)
        return report
    }

    @MainActor
    @discardableResult
    static func migrateLocally(in context: ModelContext) -> CardContentMigrationReport {
        var report = CardContentMigrationReport()
        let cards = (try? context.fetch(FetchDescriptor<FlashCard>())) ?? []
        report.scanned = cards.count

        for card in cards {
            let changed = applyLocalFixes(to: card)
            if changed.front { report.frontsUpdated += 1 }
            if changed.back { report.backsSplit += 1 }
            if !changed.front && !changed.back { report.unchanged += 1 }
        }

        if report.frontsUpdated > 0 || report.backsSplit > 0 {
            try? context.save()
            DeckCardCountService.notifyDataMaintenance()
        }
        return report
    }

    @MainActor
    static func migrate(in context: ModelContext, useAI: Bool) async -> CardContentMigrationReport {
        var report = migrateLocally(in: context)
        report.unchanged = 0

        guard useAI, APISettings.canUseAI else { return report }

        let cards = (try? context.fetch(FetchDescriptor<FlashCard>())) ?? []
        let groups = Dictionary(grouping: cards) {
            $0.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.key.isEmpty }

        for (_, group) in groups {
            let words = uniqueWords(in: group)
            guard !words.isEmpty else { continue }

            let sourceHint = group
                .compactMap { $0.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let deckName = group
                .compactMap { $0.deck?.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            for wordBatch in words.chunked(into: wordsPerGenerateCall) {
                do {
                    let drafts = try await KimiCardGenerator.generate(
                        sentence: group[0].sentence,
                        words: wordBatch,
                        sourceHint: sourceHint,
                        deckName: deckName
                    )
                    let applied = applyDrafts(drafts, to: group)
                    report.contentRefreshed += applied.refreshed
                    report.phoneticsFilled += applied.phonetics
                    report.sourcesFilled += applied.sources
                    try? context.save()
                } catch {
                    report.aiFailures += group.filter { card in
                        wordBatch.contains { $0.caseInsensitiveCompare(card.word) == .orderedSame }
                    }.count
                }
            }
        }

        if report.contentRefreshed > 0
            || report.frontsUpdated > 0
            || report.backsSplit > 0
            || report.phoneticsFilled > 0
            || report.sourcesFilled > 0 {
            DeckCardCountService.notifyDataMaintenance()
        }
        return report
    }

    // MARK: - Local (cheap, no AI)

    private struct LocalChange {
        var front = false
        var back = false
    }

    @MainActor
    private static func applyLocalFixes(to card: FlashCard) -> LocalChange {
        var change = LocalChange()

        let normalizedFront = CardContentFormatter.normalizedFront(
            front: card.front,
            sentence: card.sentence,
            word: card.word,
            cardType: card.cardType
        )
        if card.front != normalizedFront {
            card.front = normalizedFront
            change.front = true
        }

        let existingTranslation = CardContentFormatter.sentenceTranslation(card.contextNote)
        if existingTranslation == nil {
            let split = CardContentFormatter.splitLegacyBack(card.back)
            if let translation = split.translation, !translation.isEmpty {
                card.back = split.sense
                card.contextNote = translation
                change.back = true
            }
        }

        return change
    }

    // MARK: - Apply latest generator output

    private struct ApplyStats {
        var refreshed = 0
        var phonetics = 0
        var sources = 0
    }

    @MainActor
    private static func applyDrafts(
        _ drafts: [GeneratedCardDraft],
        to cards: [FlashCard]
    ) -> ApplyStats {
        var stats = ApplyStats()
        let draftIndex = Dictionary(
            drafts.map { ("\($0.word.lowercased())|\($0.cardType.rawValue)", $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for card in cards {
            let key = "\(card.word.lowercased())|\(card.cardType.rawValue)"
            guard let draft = draftIndex[key] else { continue }

            let hadPhonetic = !(card.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hadSource = !(card.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            CardContentSync.applyGeneratedContent(draft, to: card)
            stats.refreshed += 1

            let hasPhonetic = !(card.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasSource = !(card.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !hadPhonetic, hasPhonetic { stats.phonetics += 1 }
            if !hadSource, hasSource { stats.sources += 1 }
        }
        return stats
    }

    private static func uniqueWords(in cards: [FlashCard]) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for card in cards {
            let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            words.append(word)
        }
        return words
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
