import SwiftUI

enum AppColor {
    // #239678 — low-saturation deep mint (brand)
    private static let brandLight = Color(red: 0.137, green: 0.588, blue: 0.471)
    private static let brandDark = Color(red: 0.20, green: 0.70, blue: 0.58)

    static var accent: Color { Color.adaptive(light: brandLight, dark: brandDark) }
    static var accentStrong: Color { Color.adaptive(light: brandLight, dark: brandDark) }
    // #f2a868
    static var warning: Color { Color(red: 0.949, green: 0.659, blue: 0.408) }
    static var success: Color { brandLight }
    static var danger: Color { Color(red: 0.94, green: 0.33, blue: 0.31) }

    static var pageBackground: Color {
        // #f8f9fa
        Color.adaptive(
            light: Color(red: 0.973, green: 0.976, blue: 0.980),
            dark: Color(red: 0.07, green: 0.08, blue: 0.09)
        )
    }

    static var surface: Color {
        Color.adaptive(
            light: .white,
            dark: Color(red: 0.11, green: 0.12, blue: 0.14)
        )
    }

    static var surfaceMuted: Color {
        Color.adaptive(
            light: Color(red: 0.95, green: 0.96, blue: 0.97),
            dark: Color(red: 0.14, green: 0.15, blue: 0.17)
        )
    }

    static var border: Color {
        // #eeeeee
        Color.adaptive(
            light: Color(red: 0.933, green: 0.933, blue: 0.933),
            dark: Color.white.opacity(0.08)
        )
    }

    /// Soft idle input border — less gray/cheap than full `border`.
    static var borderSubtle: Color {
        Color.adaptive(
            light: Color.black.opacity(0.06),
            dark: Color.white.opacity(0.06)
        )
    }

    static var borderFocus: Color {
        Color.adaptive(
            light: Color.black.opacity(0.14),
            dark: Color.white.opacity(0.18)
        )
    }

    static var textPrimary: Color {
        // #111111 / #333333 for body via textBody
        Color.adaptive(
            light: Color(red: 0.067, green: 0.067, blue: 0.067),
            dark: Color(red: 0.95, green: 0.96, blue: 0.97)
        )
    }

    static var textBody: Color {
        Color.adaptive(
            light: Color(red: 0.2, green: 0.2, blue: 0.2),
            dark: Color(red: 0.90, green: 0.91, blue: 0.92)
        )
    }

    static var textSecondary: Color {
        // #666666
        Color.adaptive(
            light: Color(red: 0.4, green: 0.4, blue: 0.4),
            dark: Color(red: 0.65, green: 0.68, blue: 0.72)
        )
    }

    static var textTertiary: Color {
        // #999999
        Color.adaptive(
            light: Color(red: 0.6, green: 0.6, blue: 0.6),
            dark: Color(red: 0.55, green: 0.58, blue: 0.62)
        )
    }

    static var navTitle: Color { textSecondary }
    static var navTitleSecondary: Color { textBody }

    static func accentBackground(_ opacity: Double = 0.12) -> Color {
        accent.opacity(opacity)
    }

    static func successBackground(_ opacity: Double = 0.14) -> Color {
        success.opacity(opacity)
    }

    static func warningBackground(_ opacity: Double = 0.14) -> Color {
        warning.opacity(opacity)
    }

    static func ratingAgainBackground(_ opacity: Double = 0.12) -> Color {
        danger.opacity(opacity)
    }

    static func ratingHardBackground(_ opacity: Double = 0.18) -> Color {
        warning.opacity(opacity)
    }

    static func ratingEasyBackground(_ opacity: Double = 0.14) -> Color {
        success.opacity(opacity)
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
    static let card: CGFloat = 12
    static let button: CGFloat = 8
    static let input: CGFloat = 6
    static let iconButton: CGFloat = 20
    static let sheet: CGFloat = 16
}

enum AppFont {
    static func pageTitle() -> Font { .system(size: 22, weight: .semibold) }
    static func sectionTitle() -> Font { .system(size: 17, weight: .semibold) }
    static func studyWord() -> Font { .system(size: 28, weight: .semibold) }
    static func body() -> Font { .system(size: 16, weight: .regular) }
    static func secondary() -> Font { .system(size: 14, weight: .regular) }
    static func caption() -> Font { .system(size: 13, weight: .regular) }
    static func captionSecondary() -> Font { .system(size: 12, weight: .regular) }
    static func helper() -> Font { .system(size: 12, weight: .regular) }
    static func weak() -> Font { .system(size: 11, weight: .light) }
    static func navTitle() -> Font { .system(size: 14, weight: .medium) }
    static func statValue() -> Font { .system(size: 22, weight: .semibold) }
    static func statLabel() -> Font { .system(size: 12, weight: .regular) }
}

enum AppIcon {
    static let weight: Font.Weight = .regular
    static let toolbarSize: CGFloat = 20
    static let emptyStateSize: CGFloat = 40

    static func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: toolbarSize, weight: weight))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, prominent ? 16 : 12)
            .foregroundStyle(isEnabled ? Color.white : AppColor.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color.adaptive(
                light: Color(red: 0.93, green: 0.94, blue: 0.95),
                dark: Color.white.opacity(0.10)
            )
        }
        return AppColor.accentStrong.opacity(isPressed ? 0.85 : 1)
    }
}

/// Compact linear icon action — 致知 UX: small circles, soft border.
struct CompactIconAction: View {
    let systemImage: String
    var title: String? = nil
    var isDisabled: Bool = false
    /// When false, keeps intrinsic width (equal icon rows).
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColor.surface, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.border.opacity(0.55), lineWidth: 0.8)
                    }
                if let title {
                    Text(title)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(title ?? systemImage)
    }
}

struct BrandMark: View {
    var body: some View {
        // Toolbar-safe: Chinese only — avoids “致…” truncation with KnoWell beside it.
        Text(L10n.brandNameZH)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(L10n.brandNameZH) \(L10n.brandNameEN)")
    }
}

/// Knowt-style pastel circular action (legacy — prefer CompactIconAction).
struct CircularActionButton: View {
    enum Tint {
        case peach, lavender, mint, sky, coral
        var fill: Color {
            switch self {
            case .peach: Color(red: 1.0, green: 0.86, blue: 0.78)
            case .lavender: Color(red: 0.88, green: 0.84, blue: 0.98)
            case .mint: Color(red: 0.78, green: 0.93, blue: 0.88)
            case .sky: Color(red: 0.78, green: 0.90, blue: 0.98)
            case .coral: Color(red: 1.0, green: 0.82, blue: 0.84)
            }
        }
        var icon: Color {
            switch self {
            case .peach: Color(red: 0.86, green: 0.42, blue: 0.28)
            case .lavender: Color(red: 0.48, green: 0.36, blue: 0.78)
            case .mint: Color(red: 0.18, green: 0.58, blue: 0.48)
            case .sky: Color(red: 0.22, green: 0.48, blue: 0.78)
            case .coral: Color(red: 0.82, green: 0.32, blue: 0.38)
            }
        }
    }

    let systemImage: String
    let title: String
    var tint: Tint = .mint
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        CompactIconAction(systemImage: systemImage, title: title, isDisabled: isDisabled, action: action)
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

struct RevealAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(AppColor.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(AppColor.surfaceMuted.opacity(configuration.isPressed ? 0.92 : 1))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(AppColor.border, lineWidth: 1)
            }
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
        VStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: AppIcon.emptyStateSize, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.accent.opacity(0.72))

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xl)
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

    func appTint() -> some View {
        tint(AppColor.accent)
    }

    func appNavTitle(_ title: String, style: AppNavTitleStyle = .primary) -> some View {
        modifier(AppNavTitleModifier(title: title, style: style))
    }

    func appListSurface() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .appPageBackground()
    }

    func appListRowSurface() -> some View {
        listRowBackground(AppColor.surface)
            .listRowSeparatorTint(AppColor.border)
    }
}

enum AppNavTitleStyle {
    case primary
    case hidden
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
    var padding: CGFloat = AppSpacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }
}

struct AppStatTile: View {
    let title: String
    let value: String
    var tint: Color = AppColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(value)
                .font(AppFont.statValue())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(title)
                .font(AppFont.statLabel())
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.border, lineWidth: 1)
        }
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
            .font(AppFont.weak())
            .foregroundStyle(AppColor.textTertiary.opacity(0.75))
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
                            .foregroundStyle(isHighlighted ? AppColor.accent : AppColor.textPrimary)
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
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(isHighlighted ? AppColor.accent.opacity(0.35) : AppColor.border, lineWidth: 1)
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
        AppColor.surface
    }
}

struct DeckFilterChip: View {
    let title: String
    var badge: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(AppFont.caption())
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isSelected ? AppColor.accentStrong : AppColor.textTertiary)
                    }
                }
                .foregroundStyle(isSelected ? AppColor.accentStrong : AppColor.textSecondary)

                Capsule()
                    .fill(isSelected ? AppColor.accent : Color.clear)
                    .frame(height: 2)
                    .frame(maxWidth: 28)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(isSelected ? AppColor.accentStrong : AppColor.textPrimary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AppColor.accentBackground(0.16) : AppColor.surfaceMuted,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? AppColor.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                }
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
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

private extension Color {
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
