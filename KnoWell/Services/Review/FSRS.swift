import Foundation

public enum ReviewRating: Int, CaseIterable, Sendable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    /// Visible review choices: Forgot / Fuzzy / Easy (Good omitted).
    public static var userChoices: [ReviewRating] { [.again, .hard, .easy] }

    /// FSRS grade: Again=1, Hard=2, Good=3, Easy=4
    public var fsrsGrade: Int {
        switch self {
        case .again: return 1
        case .hard: return 2
        case .good: return 3
        case .easy: return 4
        }
    }
}

public enum FSRSCardState: Int, Sendable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}

public struct ReviewSnapshot: Equatable, Sendable {
    public var repetitions: Int
    public var intervalDays: Double
    public var easeFactor: Double
    public var learningStep: Int
    public var nextReviewDate: Date
    public var stability: Double
    public var difficulty: Double
    public var fsrsState: FSRSCardState
    public var lapses: Int
    public var lastReviewDate: Date?

    public init(
        repetitions: Int = 0,
        intervalDays: Double = 0,
        easeFactor: Double = 2.5,
        learningStep: Int = 0,
        nextReviewDate: Date = .now,
        stability: Double = 0,
        difficulty: Double = 0,
        fsrsState: FSRSCardState = .new,
        lapses: Int = 0,
        lastReviewDate: Date? = nil
    ) {
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.learningStep = learningStep
        self.nextReviewDate = nextReviewDate
        self.stability = stability
        self.difficulty = difficulty
        self.fsrsState = fsrsState
        self.lapses = lapses
        self.lastReviewDate = lastReviewDate
    }
}

/// FSRS-4.5 scheduler (Again / Hard / Easy; Good omitted from the UI).
public enum FSRSScheduler {
    /// Default FSRS-4.5 weights.
    private static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949,
        0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698,
        0.2315, 2.9898, 0.51655, 0.6621,
    ]
    private static let decay = -0.5
    private static let factor = pow(0.9, 1.0 / decay) - 1.0
    private static let defaultRetention = 0.9
    private static let maximumIntervalDays = 36500.0
    private static let learningStepsMinutes = [1, 10]
    private static let relearningMinutes = 10

    public static func isLearningDelay(_ snapshot: ReviewSnapshot, now: Date = .now) -> Bool {
        snapshot.nextReviewDate > now
            && snapshot.nextReviewDate.timeIntervalSince(now) < 24 * 60 * 60
    }

    public static func apply(
        rating: ReviewRating,
        cardType: CardType,
        to snapshot: inout ReviewSnapshot,
        now: Date = .now
    ) {
        migrateLegacyIfNeeded(&snapshot)
        mutate(rating: rating, cardType: cardType, snapshot: &snapshot, now: now)
    }

    public static func interval(from start: Date, to end: Date) -> TimeInterval {
        max(60, end.timeIntervalSince(start))
    }

    // MARK: - Core

    private static func mutate(
        rating: ReviewRating,
        cardType: CardType,
        snapshot: inout ReviewSnapshot,
        now: Date
    ) {
        let grade = rating.fsrsGrade
        let elapsed = elapsedDays(since: snapshot.lastReviewDate, now: now, scheduled: snapshot.intervalDays)
        let retention = requestRetention(for: cardType)

        switch snapshot.fsrsState {
        case .new:
            scheduleNew(grade: grade, cardType: cardType, snapshot: &snapshot, now: now, retention: retention)
        case .learning, .relearning:
            scheduleLearning(grade: grade, snapshot: &snapshot, now: now, retention: retention)
        case .review:
            scheduleReview(grade: grade, elapsed: elapsed, snapshot: &snapshot, now: now, retention: retention)
        }

        snapshot.lastReviewDate = now
        snapshot.easeFactor = max(1.3, 11.0 - snapshot.difficulty)
        if grade == 1 {
            snapshot.repetitions = 0
        } else if snapshot.fsrsState == .review {
            snapshot.repetitions = max(1, snapshot.repetitions + 1)
        }
    }

    private static func scheduleNew(
        grade: Int,
        cardType: CardType,
        snapshot: inout ReviewSnapshot,
        now: Date,
        retention: Double
    ) {
        snapshot.difficulty = initialDifficulty(grade: grade)
        snapshot.stability = initialStability(grade: grade, cardType: cardType)
        snapshot.learningStep = 0

        if grade == 1 {
            snapshot.fsrsState = .learning
            snapshot.learningStep = 0
            snapshot.intervalDays = 0
            snapshot.nextReviewDate = addMinutes(learningStepsMinutes[0], to: now)
        } else if grade == 2 {
            snapshot.fsrsState = .learning
            snapshot.learningStep = 1
            snapshot.intervalDays = 0
            snapshot.nextReviewDate = addMinutes(learningStepsMinutes[1], to: now)
        } else {
            graduateToReview(snapshot: &snapshot, now: now, retention: retention)
        }
    }

    private static func scheduleLearning(
        grade: Int,
        snapshot: inout ReviewSnapshot,
        now: Date,
        retention: Double
    ) {
        if snapshot.difficulty <= 0 {
            snapshot.difficulty = initialDifficulty(grade: grade)
        }
        if snapshot.stability <= 0 {
            snapshot.stability = initialStability(grade: grade, cardType: .definition)
        }

        snapshot.difficulty = nextDifficulty(d: snapshot.difficulty, grade: grade)
        snapshot.stability = nextShortTermStability(s: snapshot.stability, grade: grade)

        let steps = shortTermSteps(for: snapshot.fsrsState)
        let currentStep = min(max(snapshot.learningStep, 0), steps.count - 1)

        if grade == 1 {
            snapshot.learningStep = 0
            snapshot.intervalDays = 0
            snapshot.nextReviewDate = addMinutes(steps[0], to: now)
            return
        }

        if grade == 4 {
            graduateToReview(snapshot: &snapshot, now: now, retention: retention)
            return
        }

        let nextStep = currentStep + 1
        if nextStep < steps.count {
            snapshot.learningStep = nextStep
            snapshot.intervalDays = 0
            snapshot.nextReviewDate = addMinutes(steps[nextStep], to: now)
            return
        }

        graduateToReview(snapshot: &snapshot, now: now, retention: retention)
    }

    private static func shortTermSteps(for state: FSRSCardState) -> [Int] {
        state == .relearning ? [relearningMinutes] : learningStepsMinutes
    }

    private static func scheduleReview(
        grade: Int,
        elapsed: Double,
        snapshot: inout ReviewSnapshot,
        now: Date,
        retention: Double
    ) {
        let d = max(snapshot.difficulty, 1)
        let s = max(snapshot.stability, 0.1)
        let r = retrievability(elapsed: elapsed, stability: s)
        snapshot.difficulty = nextDifficulty(d: d, grade: grade)

        if grade == 1 {
            snapshot.stability = nextForgetStability(d: snapshot.difficulty, s: s, r: r)
            snapshot.lapses += 1
            snapshot.fsrsState = .relearning
            snapshot.learningStep = 0
            snapshot.intervalDays = 0
            snapshot.nextReviewDate = addMinutes(relearningMinutes, to: now)
            return
        }

        snapshot.stability = nextRecallStability(d: snapshot.difficulty, s: s, r: r, grade: grade)
        graduateToReview(snapshot: &snapshot, now: now, retention: retention)
    }

    private static func graduateToReview(
        snapshot: inout ReviewSnapshot,
        now: Date,
        retention: Double
    ) {
        snapshot.fsrsState = .review
        snapshot.learningStep = 0
        let days = nextInterval(stability: snapshot.stability, retention: retention)
        snapshot.intervalDays = days
        snapshot.nextReviewDate = addDays(days, to: now)
    }

    private static func migrateLegacyIfNeeded(_ snapshot: inout ReviewSnapshot) {
        guard snapshot.stability <= 0 else { return }
        if snapshot.intervalDays > 0 || snapshot.repetitions > 0 {
            snapshot.stability = max(0.1, snapshot.intervalDays > 0 ? snapshot.intervalDays : 1)
            snapshot.difficulty = clamp(11.0 - snapshot.easeFactor, 1, 10)
            snapshot.fsrsState = .review
            return
        }
        if snapshot.learningStep > 0 {
            snapshot.stability = max(0.1, w[0])
            snapshot.difficulty = clamp(11.0 - snapshot.easeFactor, 1, 10)
            snapshot.fsrsState = .learning
        }
    }

    private static func requestRetention(for cardType: CardType) -> Double {
        cardType == .appreciation ? 0.92 : defaultRetention
    }

    private static func initialStability(grade: Int, cardType: CardType) -> Double {
        let index = min(max(grade, 1), 4) - 1
        let factor = cardType == .appreciation ? 1.35 : 1.0
        return max(0.1, w[index] * factor)
    }

    private static func initialDifficulty(grade: Int) -> Double {
        clamp(w[4] - Double(grade - 3) * w[5], 1, 10)
    }

    private static func nextDifficulty(d: Double, grade: Int) -> Double {
        let next = d - w[6] * Double(grade - 3)
        let reverted = w[7] * initialDifficulty(grade: 3) + (1 - w[7]) * next
        return clamp(reverted, 1, 10)
    }

    private static func nextShortTermStability(s: Double, grade: Int) -> Double {
        max(0.1, s * exp(w[17] * (Double(grade) - 3 + w[18])))
    }

    private static func nextRecallStability(d: Double, s: Double, r: Double, grade: Int) -> Double {
        let hardPenalty = grade == 2 ? w[15] : 1.0
        let easyBonus = grade == 4 ? w[16] : 1.0
        let growth = exp(w[8])
            * (11 - d)
            * pow(s, -w[9])
            * (exp((1 - r) * w[10]) - 1)
        return max(0.1, s * (1 + growth * hardPenalty * easyBonus))
    }

    private static func nextForgetStability(d: Double, s: Double, r: Double) -> Double {
        max(
            0.1,
            w[11]
                * pow(d, -w[12])
                * (pow(s + 1, w[13]) - 1)
                * exp((1 - r) * w[14])
        )
    }

    private static func retrievability(elapsed: Double, stability: Double) -> Double {
        pow(1 + elapsed / (9 * max(stability, 0.1)), -1)
    }

    private static func nextInterval(stability: Double, retention: Double) -> Double {
        let s = max(stability, 0.1)
        let raw = (s / factor) * (pow(retention, 1 / decay) - 1)
        let days = raw.isFinite ? raw : 1
        return min(maximumIntervalDays, max(1, round(days)))
    }

    private static func elapsedDays(since last: Date?, now: Date, scheduled: Double) -> Double {
        guard let last else { return max(scheduled, 0) }
        return max(0, now.timeIntervalSince(last) / 86_400)
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value))
    }

    private static func addMinutes(_ minutes: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    private static func addDays(_ days: Double, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: Int(days * 24 * 60), to: date) ?? date
    }
}
