import Foundation
import Observation

@Observable
@MainActor
final class ReviewSettingsStore {
    static let shared = ReviewSettingsStore()

    private(set) var revision = 0

    var dailyNewLimit: Int
    var dailyReviewLimit: Int
    var reviewDeckID: UUID?
    var cardRevealStyle: ReviewCardRevealStyle

    private init() {
        dailyNewLimit = ReviewSettings.dailyNewLimit
        dailyReviewLimit = ReviewSettings.dailyReviewLimit
        reviewDeckID = ReviewSettings.reviewDeckID
        cardRevealStyle = ReviewSettings.cardRevealStyle
    }

    func reloadFromPersistence() {
        dailyNewLimit = ReviewSettings.dailyNewLimit
        dailyReviewLimit = ReviewSettings.dailyReviewLimit
        reviewDeckID = ReviewSettings.reviewDeckID
        cardRevealStyle = ReviewSettings.cardRevealStyle
        revision += 1
    }

    func persist() {
        ReviewSettings.dailyNewLimit = dailyNewLimit
        ReviewSettings.dailyReviewLimit = dailyReviewLimit
        ReviewSettings.reviewDeckID = reviewDeckID
        ReviewSettings.cardRevealStyle = cardRevealStyle
        revision += 1
    }

    func setReviewDeckID(_ deckID: UUID?) {
        reviewDeckID = deckID
        ReviewSettings.reviewDeckID = deckID
        revision += 1
    }

    func setCardRevealStyle(_ style: ReviewCardRevealStyle) {
        cardRevealStyle = style
        ReviewSettings.cardRevealStyle = style
        revision += 1
    }
}
