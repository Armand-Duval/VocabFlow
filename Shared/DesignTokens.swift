import SwiftUI

enum AppSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
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
    static func caption() -> Font { .caption }
    static func captionSecondary() -> Font { .caption.weight(.medium) }
}

enum AppIcon {
    static let tabWeight: Font.Weight = .regular
}
