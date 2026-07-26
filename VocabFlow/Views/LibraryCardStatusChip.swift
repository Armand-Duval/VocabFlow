import SwiftUI

struct LibraryCardStatusChip: View {
    let card: FlashCard

    var body: some View {
        if ReviewScheduler.isDue(card) {
            StatusChip(text: L10n.dueForReview, style: .due)
        } else if card.isNewCard {
            StatusChip(text: L10n.librarySRSNew, style: .new)
        } else {
            StatusChip(
                text: L10n.nextReview(card.nextReviewDate.formatted(date: .abbreviated, time: .shortened)),
                style: .scheduled
            )
        }
    }
}
