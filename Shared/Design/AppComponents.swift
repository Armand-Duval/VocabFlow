import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppColor {
    // Ink & 黛青 — warm paper + ink teal A (#1A5A68), distinct from bright exam-app greens
    private static let accentLight = Color(red: 0.102, green: 0.353, blue: 0.408)
    private static let accentDark = Color(red: 0.290, green: 0.604, blue: 0.667)

    static var accent: Color { Color.adaptive(light: accentLight, dark: accentDark) }
    static var accentStrong: Color { Color.adaptive(light: accentLight, dark: accentDark) }
    // Rating-only — not used for status chips
    static var warning: Color { Color(red: 0.722, green: 0.537, blue: 0.239) }
    static var success: Color { Color(red: 0.42, green: 0.62, blue: 0.48) }
    static var danger: Color { Color(red: 0.769, green: 0.361, blue: 0.329) }

    static var pageBackground: Color {
        // #F6F5F2 warm paper
        Color.adaptive(
            light: Color(red: 0.965, green: 0.961, blue: 0.949),
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
            light: Color(red: 0.945, green: 0.941, blue: 0.929),
            dark: Color(red: 0.14, green: 0.15, blue: 0.17)
        )
    }

    static var border: Color {
        Color.adaptive(
            light: Color.black.opacity(0.08),
            dark: Color.white.opacity(0.08)
        )
    }

    static var borderSubtle: Color {
        Color.adaptive(
            light: Color.black.opacity(0.04),
            dark: Color.white.opacity(0.05)
        )
    }

    static var borderFocus: Color {
        Color.adaptive(
            light: Color.black.opacity(0.12),
            dark: Color.white.opacity(0.16)
        )
    }

    static var textPrimary: Color {
        // Ink #1A1A1A
        Color.adaptive(
            light: Color(red: 0.102, green: 0.102, blue: 0.102),
            dark: Color(red: 0.95, green: 0.96, blue: 0.97)
        )
    }

    static var textBody: Color {
        Color.adaptive(
            light: Color(red: 0.18, green: 0.18, blue: 0.18),
            dark: Color(red: 0.90, green: 0.91, blue: 0.92)
        )
    }

    static var textSecondary: Color {
        Color.adaptive(
            light: Color(red: 0.42, green: 0.40, blue: 0.38),
            dark: Color(red: 0.65, green: 0.68, blue: 0.72)
        )
    }

    static var textTertiary: Color {
        // Muted #8A8780
        Color.adaptive(
            light: Color(red: 0.541, green: 0.529, blue: 0.502),
            dark: Color(red: 0.55, green: 0.58, blue: 0.62)
        )
    }

    /// Softest ink — quota / tip / footnotes (below tertiary).
    static var textMuted: Color {
        Color.adaptive(
            light: Color(red: 0.635, green: 0.616, blue: 0.588),
            dark: Color(red: 0.48, green: 0.50, blue: 0.54)
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
    /// Between major page zones (due ↔ 今日一句).
    static let section: CGFloat = 28
    static let formSection: CGFloat = 16
}

enum AppRadius {
    static let chip: CGFloat = 999
    static let card: CGFloat = 12
    static let button: CGFloat = 8
    static let input: CGFloat = 6
    static let iconButton: CGFloat = 20
    static let sheet: CGFloat = 16
    static let tabPill: CGFloat = 10
}

enum AppShadow {
    /// Single paper-lift recipe used by cards, inputs, chips, CTAs.
    static let radius: CGFloat = 8
    static let y: CGFloat = 2

    static func color(for colorScheme: ColorScheme, emphasized: Bool = false) -> Color {
        let base = colorScheme == .dark ? 0.32 : 0.045
        return Color.black.opacity(emphasized ? base + 0.02 : base)
    }

    static func card(_ colorScheme: ColorScheme = .light) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (color(for: colorScheme), radius, y)
    }

    static func pressed(_ colorScheme: ColorScheme = .light) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (color(for: colorScheme, emphasized: true), 4, 1)
    }

    static func focusAccent() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (AppColor.accent.opacity(0.10), radius, y)
    }
}

enum AppFont {
    static func pageTitle() -> Font { .system(size: 22, weight: .semibold) }
    static func sectionTitle() -> Font { .system(size: 17, weight: .semibold) }
    static func studyWord() -> Font { .system(size: 28, weight: .semibold) }
    /// Quiet literary line — New York / SF Serif when available.
    static func literaryQuote() -> Font {
        .system(size: 18, weight: .regular, design: .serif)
    }
    static func body() -> Font { .system(size: 16, weight: .regular) }
    static func secondary() -> Font { .system(size: 14, weight: .regular) }
    static func caption() -> Font { .system(size: 13, weight: .regular) }
    static func captionSecondary() -> Font { .system(size: 12, weight: .regular) }
    static func helper() -> Font { .system(size: 12, weight: .regular) }
    static func weak() -> Font { .system(size: 11, weight: .light) }
    static func navTitle() -> Font { .system(size: 14, weight: .medium) }
    static func statValue() -> Font { .system(size: 22, weight: .semibold) }
    static func heroValue() -> Font { .system(size: 40, weight: .semibold) }
    static func heroValueCompact() -> Font { .system(size: 28, weight: .semibold) }
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

/// Shared press feedback for plain / chip / icon actions.
struct SoftPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let shadow = configuration.isPressed ? AppShadow.pressed(colorScheme) : AppShadow.card(colorScheme)
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, prominent ? 16 : 12)
            .foregroundStyle(isEnabled ? Color.white : AppColor.accent.opacity(0.52))
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .shadow(
                color: isEnabled ? shadow.color : .clear,
                radius: shadow.radius,
                y: shadow.y
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            // Soft accent wash — reads disabled without cement gray.
            return AppColor.accentBackground(0.14)
        }
        // Slightly deeper at rest for clearer primary affordance.
        return AppColor.accentStrong.opacity(isPressed ? 0.86 : 1)
    }
}

/// Inline text action — paper UI quick links (no icon circles).
struct TextLinkAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption().weight(.medium))
                .foregroundStyle(AppColor.accentStrong)
        }
        .buttonStyle(SoftPressButtonStyle(pressedScale: 0.98, pressedOpacity: 0.88))
    }
}

/// Compact linear icon action — 致知 UX: soft rounded square, not heavy circles.
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
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        AppColor.surface,
                        in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                            .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
                    }
                    .appSoftShadow()
                if let title {
                    Text(title)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(title ?? systemImage)
    }
}

struct BrandMark: View {
    var body: some View {
        // Quiet wordmark — no fill chip; keep left corner light.
        Text(L10n.brandNameZH)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(L10n.brandNameZH) \(L10n.brandNameEN)")
    }
}

/// Soft surface cluster for toolbar icon groups (library trailing tools).
struct ToolbarIconCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppColor.surface, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
        }
        .appSoftShadow()
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
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
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
                    .fill(AppColor.surfaceMuted.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
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

    /// Soft paper elevation for surface cards / CTAs.
    func appSoftShadow(emphasized: Bool = false) -> some View {
        modifier(AppSoftShadowModifier(emphasized: emphasized))
    }

    /// Input / editor chrome with quiet focus ring.
    func appInputSurface(isFocused: Bool = false) -> some View {
        modifier(AppInputSurfaceModifier(isFocused: isFocused))
    }
}

private struct AppSoftShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var emphasized: Bool

    func body(content: Content) -> some View {
        let shadow = emphasized ? AppShadow.pressed(colorScheme) : AppShadow.card(colorScheme)
        content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

private struct AppInputSurfaceModifier: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        let focusShadow = AppShadow.focusAccent()
        content
            .background(
                AppColor.surface,
                in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(
                        isFocused ? AppColor.accent.opacity(0.32) : AppColor.borderSubtle,
                        lineWidth: isFocused ? 1.2 : 1
                    )
            }
            .shadow(
                color: isFocused ? focusShadow.color : .clear,
                radius: focusShadow.radius,
                y: focusShadow.y
            )
            .animation(.easeInOut(duration: 0.16), value: isFocused)
    }
}

enum AppTabBarChrome {
    static func apply() {
        #if canImport(UIKit)
        let paper = UIColor(AppColor.pageBackground)
        let accent = UIColor(AppColor.accent)
        let muted = UIColor(AppColor.textTertiary)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = paper
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.06)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = muted
        item.normal.titleTextAttributes = [
            .foregroundColor: muted,
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ]
        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [
            .foregroundColor: accent,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = muted
        #endif
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
    var bordered: Bool = false
    /// Soft paper lift. Turn off inside nested list rows if needed.
    var elevated: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: shape)
            .overlay {
                if bordered {
                    shape.strokeBorder(AppColor.border, lineWidth: 1)
                }
            }
            .modifier(ConditionalSoftShadow(enabled: elevated))
    }
}

private struct ConditionalSoftShadow: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.appSoftShadow()
        } else {
            content
        }
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
    }
}

struct HighlightedText: View {
    let text: String
    let terms: [String]
    var font: Font = AppFont.body()
    var lineLimit: Int?
    var emphasizeForeground: Bool = false

    init(
        text: String,
        query: String,
        font: Font = AppFont.body(),
        lineLimit: Int? = nil,
        emphasizeForeground: Bool = false
    ) {
        self.text = text
        self.terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        self.font = font
        self.lineLimit = lineLimit
        self.emphasizeForeground = emphasizeForeground
    }

    init(
        text: String,
        terms: [String],
        font: Font = AppFont.body(),
        lineLimit: Int? = nil,
        emphasizeForeground: Bool = false
    ) {
        self.text = text
        self.terms = terms.filter { !$0.isEmpty }
        self.font = font
        self.lineLimit = lineLimit
        self.emphasizeForeground = emphasizeForeground
    }

    var body: some View {
        Text(highlighted)
            .font(font)
            .lineLimit(lineLimit)
    }

    private var highlighted: AttributedString {
        var result = AttributedString(text)
        guard !terms.isEmpty else { return result }

        // Longer terms first to prefer fuller matches.
        for term in terms.sorted(by: { $0.count > $1.count }) {
            var searchStart = result.startIndex
            while searchStart < result.endIndex,
                  let found = result[searchStart...].range(of: term, options: .caseInsensitive) {
                result[found].backgroundColor = AppColor.accentBackground(0.24)
                result[found].font = font.weight(.semibold)
                if emphasizeForeground {
                    result[found].foregroundColor = AppColor.accent
                }
                searchStart = found.upperBound
            }
        }
        return result
    }
}

struct AppTabIcon: View {
    let systemName: String
    var isSelected: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .fontWeight(isSelected ? .semibold : AppIcon.weight)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

struct AppSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppFont.weak())
            .foregroundStyle(AppColor.textTertiary.opacity(0.55))
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
        .buttonStyle(SoftPressButtonStyle())
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
                    .fill(isSelected ? AppColor.accent.opacity(0.55) : Color.clear)
                    .frame(height: 1.5)
                    .frame(maxWidth: 22)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .opacity(isSelected ? 1 : 0.78)
        }
        .buttonStyle(SoftPressButtonStyle(pressedScale: 0.98, pressedOpacity: 0.88))
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
        .buttonStyle(SoftPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.88))
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

/// Quiet due/total meter for deck rows — not a dashboard gauge.
struct DeckDueMeter: View {
    let dueCount: Int
    let totalCount: Int

    private var progress: CGFloat {
        guard totalCount > 0 else { return 0 }
        return min(1, CGFloat(dueCount) / CGFloat(totalCount))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.surfaceMuted)
                Capsule()
                    .fill(dueCount > 0 ? AppColor.accent.opacity(0.55) : AppColor.borderSubtle)
                    .frame(width: max(4, geo.size.width * progress))
            }
        }
        .frame(height: 3)
        .accessibilityLabel(L10n.deckDueMeterA11y(due: dueCount, total: totalCount))
    }
}

private extension Color {
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
