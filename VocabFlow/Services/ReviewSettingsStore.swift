import Foundation
import Observation

@Observable
@MainActor
final class ReviewSettingsStore {
    static let shared = ReviewSettingsStore()

    private(set) var revision = 0

    var dailyNewLimit: Int
    var dailyReviewLimit: Int

    private init() {
        dailyNewLimit = ReviewSettings.dailyNewLimit
        dailyReviewLimit = ReviewSettings.dailyReviewLimit
    }

    func reloadFromPersistence() {
        dailyNewLimit = ReviewSettings.dailyNewLimit
        dailyReviewLimit = ReviewSettings.dailyReviewLimit
        revision += 1
    }

    func persist() {
        ReviewSettings.dailyNewLimit = dailyNewLimit
        ReviewSettings.dailyReviewLimit = dailyReviewLimit
        revision += 1
    }
}
