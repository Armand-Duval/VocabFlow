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
}

struct ReviewSnapshot {
    var repetitions: Int
    var intervalDays: Double
    var easeFactor: Double
    var learningStep: Int
    var nextReviewDate: Date

    init(from card: FlashCard) {
        repetitions = card.repetitions
        intervalDays = card.intervalDays
        easeFactor = card.easeFactor
        learningStep = card.learningStep
        nextReviewDate = card.nextReviewDate
    }

    func write(to card: FlashCard) {
        card.repetitions = repetitions
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.learningStep = learningStep
        card.nextReviewDate = nextReviewDate
    }
}

enum ReviewScheduler {
    private static let learningStepsMinutes = [1, 10]
    private static let lapseHours = 10

    static func isDue(_ card: FlashCard, now: Date = .now) -> Bool {
        card.nextReviewDate <= now
    }

    static func preview(rating: ReviewRating, for card: FlashCard, now: Date = .now) -> ReviewSnapshot {
        var snapshot = ReviewSnapshot(from: card)
        mutate(rating: rating, snapshot: &snapshot, now: now)
        return snapshot
    }

    static func intervalLabel(for card: FlashCard, rating: ReviewRating, now: Date = .now) -> String {
        let snapshot = preview(rating: rating, for: card, now: now)
        return formatInterval(from: now, to: snapshot.nextReviewDate)
    }

    static func isLearningDelay(_ snapshot: ReviewSnapshot, now: Date = .now) -> Bool {
        snapshot.nextReviewDate > now
            && snapshot.nextReviewDate.timeIntervalSince(now) < 24 * 60 * 60
    }

    static func resetProgress(for card: FlashCard, now: Date = .now) {
        card.repetitions = 0
        card.intervalDays = 0
        card.easeFactor = 2.5
        card.reviewCount = 0
        card.learningStep = 0
        card.nextReviewDate = now
    }

    static func apply(rating: ReviewRating, to card: FlashCard, now: Date = .now) {
        let wasNewCard = card.isNewCard
        var snapshot = ReviewSnapshot(from: card)
        mutate(rating: rating, snapshot: &snapshot, now: now)
        snapshot.write(to: card)
        card.reviewCount += 1
        ReviewSettings.recordStudy(wasNewCard: wasNewCard, now: now)
    }

    private static func mutate(rating: ReviewRating, snapshot: inout ReviewSnapshot, now: Date) {
        switch rating {
        case .again:
            snapshot.easeFactor = max(1.3, snapshot.easeFactor - 0.2)
            if snapshot.learningStep < learningStepsMinutes.count {
                let minutes = learningStepsMinutes[snapshot.learningStep]
                snapshot.learningStep += 1
                snapshot.repetitions = 0
                snapshot.intervalDays = 0
                snapshot.nextReviewDate = addMinutes(minutes, to: now)
            } else {
                snapshot.learningStep = 0
                snapshot.repetitions = 0
                snapshot.intervalDays = 0
                snapshot.nextReviewDate = addHours(lapseHours, to: now)
            }

        case .hard:
            snapshot.learningStep = 0
            snapshot.repetitions += 1
            snapshot.easeFactor = max(1.3, snapshot.easeFactor - 0.15)
            snapshot.intervalDays = max(1, snapshot.intervalDays * 1.2)
            snapshot.nextReviewDate = addDays(snapshot.intervalDays, to: now)

        case .good:
            snapshot.learningStep = 0
            snapshot.repetitions += 1
            if snapshot.repetitions == 1 {
                snapshot.intervalDays = 1
            } else if snapshot.repetitions == 2 {
                snapshot.intervalDays = 3
            } else {
                snapshot.intervalDays = round(snapshot.intervalDays * snapshot.easeFactor)
            }
            snapshot.nextReviewDate = addDays(snapshot.intervalDays, to: now)

        case .easy:
            snapshot.learningStep = 0
            snapshot.repetitions += 1
            snapshot.easeFactor += 0.15
            snapshot.intervalDays = max(4, round(snapshot.intervalDays * snapshot.easeFactor * 1.3))
            snapshot.nextReviewDate = addDays(snapshot.intervalDays, to: now)
        }
    }

    static func formatInterval(from start: Date, to end: Date) -> String {
        let seconds = max(60, end.timeIntervalSince(start))
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

    private static func addMinutes(_ minutes: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    private static func addHours(_ hours: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: date) ?? date
    }

    private static func addDays(_ days: Double, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: Int(days * 24 * 60), to: date) ?? date
    }
}
