import Foundation

struct ReviewQueuePlan {
    let sessionCards: [FlashCard]
    let newStudiedToday: Int
    let reviewStudiedToday: Int
    let newLimit: Int
    let reviewLimit: Int
    let deferredNewCount: Int
    let deferredReviewCount: Int

    var deferredTotalCount: Int {
        deferredNewCount + deferredReviewCount
    }

    var hasDeferredCards: Bool {
        deferredTotalCount > 0
    }
}

enum ReviewQueueBuilder {
    static func cards(in deckID: UUID?, from allCards: [FlashCard]) -> [FlashCard] {
        guard let deckID else { return allCards }
        return allCards.filter { $0.deck?.id == deckID }
    }

    static func plan(
        from allCards: [FlashCard],
        dailyNewLimit: Int = ReviewSettings.dailyNewLimit,
        dailyReviewLimit: Int = ReviewSettings.dailyReviewLimit,
        now: Date = .now
    ) -> ReviewQueuePlan {
        ReviewSettings.resetDailyCountsIfNeeded(now: now)

        let due = allCards.filter { ReviewScheduler.isDue($0, now: now) }
        let dueNew = due
            .filter(\.isNewCard)
            .sorted { $0.createdAt < $1.createdAt }
        let dueReview = due
            .filter { !$0.isNewCard }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }

        let newRemaining = remainingQuota(limit: dailyNewLimit, studied: ReviewSettings.newStudiedToday)
        let reviewRemaining = remainingQuota(limit: dailyReviewLimit, studied: ReviewSettings.reviewStudiedToday)

        let selectedNew = Array(dueNew.prefix(newRemaining))
        let selectedReview = Array(dueReview.prefix(reviewRemaining))
        let sessionCards = shuffledAvoidingAdjacentSameWord(selectedNew + selectedReview)

        return ReviewQueuePlan(
            sessionCards: sessionCards,
            newStudiedToday: ReviewSettings.newStudiedToday,
            reviewStudiedToday: ReviewSettings.reviewStudiedToday,
            newLimit: dailyNewLimit,
            reviewLimit: dailyReviewLimit,
            deferredNewCount: max(0, dueNew.count - selectedNew.count),
            deferredReviewCount: max(0, dueReview.count - selectedReview.count)
        )
    }

    /// 今日配额内可立即复习的数量（与 Review 页实际队列一致）。
    static func sessionDueCount(
        from allCards: [FlashCard],
        dailyNewLimit: Int = ReviewSettings.dailyNewLimit,
        dailyReviewLimit: Int = ReviewSettings.dailyReviewLimit,
        now: Date = .now
    ) -> Int {
        plan(
            from: allCards,
            dailyNewLimit: dailyNewLimit,
            dailyReviewLimit: dailyReviewLimit,
            now: now
        ).sessionCards.count
    }

    /// Shuffle, then greedily avoid consecutive cards that share the same word
    /// or the same sentence (multi-word extracts from one line).
    /// Unavoidable only when every remaining card collides with the previous one.
    static func shuffledAvoidingAdjacentSameWord(_ cards: [FlashCard]) -> [FlashCard] {
        guard cards.count > 1 else { return cards }

        var pool = cards.shuffled()
        var result: [FlashCard] = []
        result.reserveCapacity(pool.count)

        while !pool.isEmpty {
            let previous = result.last
            if let previous,
               let index = pool.firstIndex(where: { !sharesStudyContext($0, with: previous) }) {
                result.append(pool.remove(at: index))
            } else {
                result.append(pool.removeFirst())
            }
        }
        return result
    }

    static func wordKey(for card: FlashCard) -> String {
        wordKey(card)
    }

    static func sharesStudyContext(_ lhs: FlashCard, with rhs: FlashCard) -> Bool {
        if wordKey(lhs) == wordKey(rhs) { return true }
        guard let leftSentence = sentenceKey(lhs), let rightSentence = sentenceKey(rhs) else {
            return false
        }
        return leftSentence == rightSentence
    }

    private static func wordKey(_ card: FlashCard) -> String {
        card.word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func sentenceKey(_ card: FlashCard) -> String? {
        let sentence = card.sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return sentence.isEmpty ? nil : sentence
    }

    private static func remainingQuota(limit: Int, studied: Int) -> Int {
        if limit == 0 { return Int.max }
        return max(0, limit - studied)
    }
}

extension FlashCard {
    /// 从未成功进入复习阶段的卡片（含刚创建、Again 后重置的卡片）。
    var isNewCard: Bool {
        if reviewCount > 0 { return false }
        return repetitions == 0 && intervalDays == 0
    }
}
