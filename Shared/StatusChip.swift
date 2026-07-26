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
        case .scheduled, .neutral, .suspended: .secondary
        }
    }

    var background: Color {
        switch self {
        case .due: AppColor.warningBackground()
        case .new, .cardType: AppColor.accentBackground(0.12)
        case .scheduled, .neutral, .suspended: Color.secondary.opacity(0.10)
        }
    }
}

struct StatusChip: View {
    let text: String
    var style: StatusChipStyle = .neutral

    var body: some View {
        Text(text)
            .font(AppFont.captionSecondary())
            .foregroundStyle(style.foreground)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 4)
            .background(style.background, in: Capsule())
    }
}

struct CardTypeChip: View {
    let title: String

    var body: some View {
        StatusChip(text: title, style: .cardType)
    }
}
