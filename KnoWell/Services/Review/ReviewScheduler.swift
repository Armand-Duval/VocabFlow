import Foundation

extension ReviewRating {
    private var vocabularyTitle: String {
        switch self {
        case .again: L10n.ratingAgain
        case .hard: L10n.ratingHard
        case .good: L10n.ratingGood
        case .easy: L10n.ratingEasy
        }
    }

    var title: String { vocabularyTitle }

    func displayTitle(for cardType: CardType) -> String {
        if cardType == .appreciation {
            switch self {
            case .again: return L10n.ratingAppreciationAgain
            case .hard: return L10n.ratingAppreciationHard
            case .good: return L10n.ratingAppreciationGood
            case .easy: return L10n.ratingAppreciationEasy
            }
        }
        return vocabularyTitle
    }
}

extension ReviewSnapshot {
    init(from card: FlashCard) {
        self.init(
            repetitions: card.repetitions,
            intervalDays: card.intervalDays,
            easeFactor: card.easeFactor,
            learningStep: card.learningStep,
            nextReviewDate: card.nextReviewDate,
            stability: card.stability,
            difficulty: card.difficulty,
            fsrsState: FSRSCardState(rawValue: card.fsrsStateRaw) ?? .new,
            lapses: card.lapses,
            lastReviewDate: card.lastReviewDate
        )
    }

    func write(to card: FlashCard) {
        card.repetitions = repetitions
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.learningStep = learningStep
        card.nextReviewDate = nextReviewDate
        card.stability = stability
        card.difficulty = difficulty
        card.fsrsStateRaw = fsrsState.rawValue
        card.lapses = lapses
        card.lastReviewDate = lastReviewDate
    }
}

/// App-facing FSRS wrapper: SwiftData cards, labels, and study side effects.
enum ReviewScheduler {
    static func isDue(_ card: FlashCard, now: Date = .now) -> Bool {
        !card.isSuspended && card.nextReviewDate <= now
    }

    static func isActive(_ card: FlashCard) -> Bool {
        !card.isSuspended
    }

    static func preview(rating: ReviewRating, for card: FlashCard, now: Date = .now) -> ReviewSnapshot {
        var snapshot = ReviewSnapshot(from: card)
        FSRSScheduler.apply(rating: rating, cardType: card.cardType, to: &snapshot, now: now)
        return snapshot
    }

    static func intervalLabel(for card: FlashCard, rating: ReviewRating, now: Date = .now) -> String {
        let snapshot = preview(rating: rating, for: card, now: now)
        return formatInterval(from: now, to: snapshot.nextReviewDate)
    }

    static func isLearningDelay(_ snapshot: ReviewSnapshot, now: Date = .now) -> Bool {
        FSRSScheduler.isLearningDelay(snapshot, now: now)
    }

    static func resetProgress(for card: FlashCard, now: Date = .now) {
        card.repetitions = 0
        card.intervalDays = 0
        card.easeFactor = 2.5
        card.reviewCount = 0
        card.learningStep = 0
        card.nextReviewDate = now
        card.stability = 0
        card.difficulty = 0
        card.fsrsStateRaw = FSRSCardState.new.rawValue
        card.lapses = 0
        card.lastReviewDate = nil
    }

    static func apply(rating: ReviewRating, to card: FlashCard, now: Date = .now) {
        let wasNewCard = card.isNewCard
        var snapshot = ReviewSnapshot(from: card)
        FSRSScheduler.apply(rating: rating, cardType: card.cardType, to: &snapshot, now: now)
        snapshot.write(to: card)
        card.reviewCount += 1
        ReviewSettings.recordStudy(wasNewCard: wasNewCard, now: now)
        StudyActivityStore.record(word: card.word, sentence: card.sentence, now: now)
    }

    static func formatInterval(from start: Date, to end: Date) -> String {
        let seconds = FSRSScheduler.interval(from: start, to: end)
        if seconds < 3600 {
            let minutes = Int(round(seconds / 60))
            return L10n.intervalMinutes(minutes)
        }
        if seconds < 86_400 {
            let hours = Int(round(seconds / 3600))
            return L10n.intervalHours(hours)
        }
        let days = Int(round(seconds / 86_400))
        return L10n.intervalDays(days)
    }
}
