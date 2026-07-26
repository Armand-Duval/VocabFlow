import SwiftUI

enum AppColor {
    static var accent: Color { .accentColor }
    static var warning: Color { .orange }
    static var success: Color { .green }
    static var pageBackground: Color { Color(.systemGroupedBackground) }
    static var surface: Color { Color(.systemBackground) }
    /// Primary nav title gray (#666666).
    static var navTitle: Color { Color(red: 0.4, green: 0.4, blue: 0.4) }
    /// Secondary (push) pages — slightly stronger contrast.
    static var navTitleSecondary: Color { Color(red: 0.27, green: 0.27, blue: 0.27) }

    static func accentBackground(_ opacity: Double = 0.12) -> Color {
        accent.opacity(opacity)
    }

    static func successBackground(_ opacity: Double = 0.14) -> Color {
        Color.green.opacity(opacity)
    }

    static func warningBackground(_ opacity: Double = 0.14) -> Color {
        Color.orange.opacity(opacity)
    }

    static func ratingAgainBackground(_ opacity: Double = 0.12) -> Color {
        Color.red.opacity(opacity)
    }

    static func ratingHardBackground(_ opacity: Double = 0.22) -> Color {
        Color.yellow.opacity(opacity)
    }

    static func ratingEasyBackground(_ opacity: Double = 0.12) -> Color {
        Color.green.opacity(opacity)
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
    static func navTitle() -> Font { .callout.weight(.medium) }
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

    func appPageBackground() -> some View {
        background(AppColor.pageBackground)
    }

    func appNavTitle(_ title: String, style: AppNavTitleStyle = .primary) -> some View {
        modifier(AppNavTitleModifier(title: title, style: style))
    }
}

enum AppNavTitleStyle {
    /// Create / Review / Settings — inline, medium, #666.
    case primary
    /// Library — search + chips identify the page; no nav title.
    case hidden
    /// Push/detail pages — slightly darker for hierarchy.
    case secondary
}

private struct AppNavTitleModifier: ViewModifier {
    let title: String
    let style: AppNavTitleStyle

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                if style == .primary || style == .secondary {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .font(AppFont.navTitle())
                            .foregroundStyle(style == .secondary ? AppColor.navTitleSecondary : AppColor.navTitle)
                    }
                }
            }
    }
}

struct AppSurfaceCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
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

struct AppSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppFont.caption())
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

struct QuickActionChip: View {
    let systemImage: String
    let title: String
    var iconOnly: Bool = false
    var isHighlighted: Bool = false
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    iconBlock
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(chipBackground, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        iconBlock
                        Text(title)
                            .font(AppFont.captionSecondary())
                            .foregroundStyle(isHighlighted ? AppColor.accent : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.xs)
                    .background(chipBackground, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                }
            }
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .strokeBorder(AppColor.accent.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var iconBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                .fill(isHighlighted ? AppColor.accent : AppColor.accentBackground(0.12))
                .frame(width: 48, height: 48)

            if isLoading {
                ProgressView()
                    .tint(isHighlighted ? .white : AppColor.accent)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: AppIcon.weight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHighlighted ? .white : AppColor.accent)
            }
        }
    }

    private var chipBackground: some ShapeStyle {
        Color(.secondarySystemGroupedBackground)
    }
}

struct DeckFilterChip: View {
    let title: String
    var badge: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppFont.caption())
                    .lineLimit(1)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? AppColor.accent : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chipBadgeBackground, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? AppColor.accent : .primary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 6)
            .background(chipBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chipBackground: some ShapeStyle {
        isSelected ? AppColor.accentBackground(0.18) : Color.secondary.opacity(0.12)
    }

    private var chipBadgeBackground: some ShapeStyle {
        isSelected ? AppColor.accentBackground(0.28) : Color.secondary.opacity(0.14)
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
