import SwiftUI

enum StatusChipStyle {
    case due
    case new
    case scheduled
    case suspended
    case cardType
    case neutral

    var foreground: Color {
        switch self {
        case .due: AppColor.warning
        case .new, .cardType: AppColor.accent
        case .scheduled, .neutral, .suspended: AppColor.textTertiary
        }
    }

    var background: Color {
        switch self {
        case .due: AppColor.warningBackground(0.12)
        case .new, .cardType: AppColor.accentBackground(0.10)
        case .scheduled, .neutral, .suspended: AppColor.surfaceMuted
        }
    }
}

struct StatusChip: View {
    let text: String
    var style: StatusChipStyle = .neutral

    var body: some View {
        Text(text)
            .font(AppFont.weak())
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                style.background,
                // Match card radius (12) — avoid capsule vs card mismatch.
                in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            )
    }
}

struct CardTypeChip: View {
    let title: String

    var body: some View {
        StatusChip(text: title, style: .cardType)
    }
}
