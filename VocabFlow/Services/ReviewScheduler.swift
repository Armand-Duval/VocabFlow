import Foundation

enum ReviewRating: Int, CaseIterable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    var title: String {
        switch self {
        case .again: L10n.ratingAgain
        case .hard: L10n.ratingHard
        case .good: L10n.ratingGood
        case .easy: L10n.ratingEasy
        }
    }

    var subtitle: String {
        switch self {
        case .again: L10n.ratingAgainInterval
        case .hard: L10n.ratingHardInterval
        case .good: L10n.ratingGoodInterval
        case .easy: L10n.ratingEasyInterval
        }
    }
}

enum ReviewScheduler {
    static func isDue(_ card: FlashCard, now: Date = .now) -> Bool {
        card.nextReviewDate <= now
    }

    static func apply(rating: ReviewRating, to card: FlashCard, now: Date = .now) {
        switch rating {
        case .again:
            card.repetitions = 0
            card.intervalDays = 0
            card.easeFactor = max(1.3, card.easeFactor - 0.2)
            card.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 10, to: now) ?? now

        case .hard:
            card.repetitions += 1
            card.easeFactor = max(1.3, card.easeFactor - 0.15)
            card.intervalDays = max(1, card.intervalDays * 1.2)
            card.nextReviewDate = addDays(card.intervalDays, to: now)

        case .good:
            card.repetitions += 1
            if card.repetitions == 1 {
                card.intervalDays = 1
            } else if card.repetitions == 2 {
                card.intervalDays = 3
            } else {
                card.intervalDays = round(card.intervalDays * card.easeFactor)
            }
            card.nextReviewDate = addDays(card.intervalDays, to: now)

        case .easy:
            card.repetitions += 1
            card.easeFactor += 0.15
            card.intervalDays = max(4, round(card.intervalDays * card.easeFactor * 1.3))
            card.nextReviewDate = addDays(card.intervalDays, to: now)
        }
    }

    private static func addDays(_ days: Double, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: Int(days * 24 * 60), to: date) ?? date
    }
}
