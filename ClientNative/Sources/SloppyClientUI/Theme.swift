import SwiftUI

// MARK: - AppColors

public struct AppColors: Sendable, Hashable {
    public var background: Color
    public var surface: Color
    public var surfaceRaised: Color
    public var surfaceGlass: Color
    public var surfaceGlow: Color

    public var accent: Color
    public var accentCyan: Color
    public var accentAcid: Color

    public var textPrimary: Color
    public var textSecondary: Color
    public var textMuted: Color

    public var border: Color
    public var borderBold: Color

    public var statusActive: Color
    public var statusReady: Color
    public var statusDone: Color
    public var statusBlocked: Color
    public var statusWarning: Color
    public var statusNeutral: Color

    public static let dark = AppColors(
        background:     .fromHex(0x000000),
        surface:        .fromHex(0x0B1020),
        surfaceRaised:  .fromHex(0x141B33),
        surfaceGlass:   .fromHex(0x111A2E),
        surfaceGlow:    .fromHex(0x24315A),
        accent:         .fromHex(0x8B5CFF),
        accentCyan:     .fromHex(0x25D7FF),
        accentAcid:     .fromHex(0xFFB86B),
        textPrimary:    .fromHex(0xF7F4FF),
        textSecondary:  .fromHex(0xB8C3DD),
        textMuted:      .fromHex(0x66718E),
        border:         .fromHex(0x22304D),
        borderBold:     .fromHex(0x5B6FA5),
        statusActive:   .fromHex(0x25D7FF),
        statusReady:    .fromHex(0xB48CFF),
        statusDone:     .fromHex(0x5CF0A8),
        statusBlocked:  .fromHex(0xFF5A7A),
        statusWarning:  .fromHex(0xFFB86B),
        statusNeutral:  .fromHex(0x7784A3)
    )

    public static let light = AppColors(
        background:     .fromHex(0xF7FBFF),
        surface:        .fromHex(0xFFFFFF),
        surfaceRaised:  .fromHex(0xF5F7FA),
        surfaceGlass:   .fromHex(0xFFFFFF),
        surfaceGlow:    .fromHex(0xCFEAFF),
        accent:         .fromHex(0x3B82F6),
        accentCyan:     .fromHex(0x63C7FF),
        accentAcid:     .fromHex(0xD4AF37),
        textPrimary:    .fromHex(0x141518),
        textSecondary:  .fromHex(0x2F343B),
        textMuted:      .fromHex(0x6B7280),
        border:         .fromHex(0xDCE4EC),
        borderBold:     .fromHex(0xAAB8C5),
        statusActive:   .fromHex(0x2684FF),
        statusReady:    .fromHex(0x7C5CFF),
        statusDone:     .fromHex(0x16A164),
        statusBlocked:  .fromHex(0xD92D54),
        statusWarning:  .fromHex(0xB7791F),
        statusNeutral:  .fromHex(0x6B7280)
    )
}

// MARK: - AppTypography

public struct AppTypography: Sendable, Hashable {
    public var hero: Double
    public var title: Double
    public var heading: Double
    public var body: Double
    public var caption: Double
    public var micro: Double

    public static let `default` = AppTypography(
        hero:    46,
        title:   30,
        heading: 19,
        body:    15,
        caption: 12,
        micro:   10
    )
}

// MARK: - AppSpacing

public struct AppSpacing: Sendable, Hashable {
    public var xs: CGFloat
    public var s: CGFloat
    public var m: CGFloat
    public var l: CGFloat
    public var xl: CGFloat
    public var xxl: CGFloat

    public static let `default` = AppSpacing(
        xs:  4,
        s:   8,
        m:   16,
        l:   24,
        xl:  32,
        xxl: 48
    )
}

// MARK: - AppBorders

public struct AppBorders: Sendable, Hashable {
    public var thin: CGFloat
    public var medium: CGFloat
    public var thick: CGFloat

    public static let `default` = AppBorders(thin: 1, medium: 2, thick: 3)
}

// MARK: - Theme

public struct AppTheme: Sendable, Hashable {
    public var colors: AppColors
    public var typography: AppTypography
    public var spacing: AppSpacing
    public var borders: AppBorders

    public static let sloppyDark = AppTheme(
        colors: .dark,
        typography: .default,
        spacing: .default,
        borders: .default
    )

    public static let sloppyLight = AppTheme(
        colors: .light,
        typography: .default,
        spacing: .default,
        borders: .default
    )
}

public typealias Theme = AppTheme

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.sloppyDark
}

public extension EnvironmentValues {
    var theme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

public extension View {
    func theme(_ theme: AppTheme) -> some View {
        environment(\.theme, theme)
    }
}
