import SwiftUI

struct LibraryCardStatusChip: View {
    let card: FlashCard

    var body: some View {
        if card.isSuspended {
            StatusChip(text: L10n.cardSuspendedStatus, style: .suspended)
        } else if ReviewScheduler.isDue(card) {
            StatusChip(text: L10n.dueForReview, style: .due)
        }
    }
}
