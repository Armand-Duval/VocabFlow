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
        case .due, .new, .cardType: AppColor.accentStrong
        case .scheduled, .neutral, .suspended: AppColor.textTertiary
        }
    }

    var background: Color {
        switch self {
        case .due, .new, .cardType: AppColor.accentBackground(0.08)
        case .scheduled, .neutral, .suspended: AppColor.surfaceMuted
        }
    }
}

struct StatusChip: View {
    let text: String
    var style: StatusChipStyle = .neutral

    var body: some View {
        Text(text)
            .font(AppFont.weak().weight(style == .due ? .medium : .regular))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.background, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
    }
}

struct CardTypeChip: View {
    let title: String

    var body: some View {
        StatusChip(text: title, style: .cardType)
    }
}
