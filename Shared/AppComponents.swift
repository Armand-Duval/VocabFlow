import SwiftUI

enum AppColor {
    static var accent: Color { .accentColor }
    static var warning: Color { .orange }
    static var success: Color { .green }

    static func accentBackground(_ opacity: Double = 0.12) -> Color {
        accent.opacity(opacity)
    }

    static func successBackground(_ opacity: Double = 0.14) -> Color {
        Color.green.opacity(opacity)
    }

    static func warningBackground(_ opacity: Double = 0.14) -> Color {
        Color.orange.opacity(opacity)
    }
}

enum AppSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let formSection: CGFloat = 16
}

enum AppRadius {
    static let chip: CGFloat = 999
    static let card: CGFloat = 16
    static let button: CGFloat = 12
}

enum AppFont {
    static func pageTitle() -> Font { .largeTitle.bold() }
    static func sectionTitle() -> Font { .title3.weight(.semibold) }
    static func body() -> Font { .body }
    static func secondary() -> Font { .subheadline }
    static func caption() -> Font { .caption }
    static func captionSecondary() -> Font { .caption.weight(.medium) }
    static func helper() -> Font { .footnote }
}

enum AppIcon {
    static let weight: Font.Weight = .regular
    static let toolbarSize: CGFloat = 22
    static let emptyStateSize: CGFloat = 44

    static func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: toolbarSize, weight: weight))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.secondary.opacity(0.35) }
        return AppColor.accent.opacity(isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(AppColor.accent)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(AppColor.accent.opacity(configuration.isPressed ? 0.5 : 0.35), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                            .fill(AppColor.accentBackground(configuration.isPressed ? 0.16 : 0.08))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AppEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text(message)
                .font(AppFont.helper())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension View {
    func appFormSectionSpacing() -> some View {
        listSectionSpacing(AppSpacing.formSection)
    }

    func appScreenPadding() -> some View {
        padding(.horizontal, AppSpacing.md)
    }
}

struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = AppFont.body()
    var lineLimit: Int?

    var body: some View {
        Text(highlighted)
            .font(font)
            .lineLimit(lineLimit)
    }

    private var highlighted: AttributedString {
        var result = AttributedString(text)
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return result }

        for term in terms {
            var searchStart = result.startIndex
            while searchStart < result.endIndex,
                  let found = result[searchStart...].range(of: term, options: .caseInsensitive) {
                result[found].backgroundColor = AppColor.accentBackground(0.24)
                result[found].font = font.weight(.semibold)
                searchStart = found.upperBound
            }
        }
        return result
    }
}

struct AppTabIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .fontWeight(AppIcon.weight)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption())
                .foregroundStyle(isSelected ? AppColor.accent : .primary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AppColor.accentBackground(0.18) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.secondary())
        }
    }
}
