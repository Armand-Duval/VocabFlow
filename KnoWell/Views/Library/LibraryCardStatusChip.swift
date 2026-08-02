import SwiftUI

struct LibraryCardStatusChip: View {
    let card: FlashCard

    var body: some View {
        if card.isSuspended {
            Text(L10n.cardSuspendedStatus)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)
        } else if ReviewScheduler.isDue(card) {
            HStack(spacing: 5) {
                Circle()
                    .fill(AppColor.accent)
                    .frame(width: 5, height: 5)
                Text(L10n.dueForReview)
                    .font(AppFont.weak().weight(.medium))
                    .foregroundStyle(AppColor.accentStrong)
            }
        }
    }
}
