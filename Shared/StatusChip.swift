import SwiftUI

enum StatusChipStyle {
    case due
    case new
    case scheduled
    case cardType
    case neutral

    var foreground: Color {
        switch self {
        case .due: .orange
        case .new: .blue
        case .scheduled: .secondary
        case .cardType: .blue
        case .neutral: .secondary
        }
    }

    var background: Color {
        switch self {
        case .due: Color.orange.opacity(0.14)
        case .new: Color.blue.opacity(0.12)
        case .scheduled: Color.secondary.opacity(0.10)
        case .cardType: Color.blue.opacity(0.12)
        case .neutral: Color.secondary.opacity(0.12)
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
