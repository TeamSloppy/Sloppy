import AdaEngine

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

public struct AppColorsKey: ThemeKey {
    public static let defaultValue = AppColors.dark
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

public struct AppTypographyKey: ThemeKey {
    public static let defaultValue = AppTypography.default
}

// MARK: - AppSpacing

public struct AppSpacing: Sendable, Hashable {
    public var xs: Float
    public var s: Float
    public var m: Float
    public var l: Float
    public var xl: Float
    public var xxl: Float

    public static let `default` = AppSpacing(
        xs:  4,
        s:   8,
        m:   16,
        l:   24,
        xl:  32,
        xxl: 48
    )
}

public struct AppSpacingKey: ThemeKey {
    public static let defaultValue = AppSpacing.default
}

// MARK: - AppBorders

public struct AppBorders: Sendable, Hashable {
    public var thin: Float
    public var medium: Float
    public var thick: Float

    public static let `default` = AppBorders(thin: 1, medium: 2, thick: 3)
}

public struct AppBordersKey: ThemeKey {
    public static let defaultValue = AppBorders.default
}

// MARK: - Theme convenience accessors

public extension Theme {
    var colors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }

    var typography: AppTypography {
        get { self[AppTypographyKey.self] }
        set { self[AppTypographyKey.self] = newValue }
    }

    var spacing: AppSpacing {
        get { self[AppSpacingKey.self] }
        set { self[AppSpacingKey.self] = newValue }
    }

    var borders: AppBorders {
        get { self[AppBordersKey.self] }
        set { self[AppBordersKey.self] = newValue }
    }
}

// MARK: - Presets

public extension Theme {
    static let sloppyDark: Theme = {
        var t = Theme()
        t[AppColorsKey.self] = .dark
        t[AppTypographyKey.self] = .default
        t[AppSpacingKey.self] = .default
        t[AppBordersKey.self] = .default
        return t
    }()

    static let sloppyLight: Theme = {
        var t = Theme()
        t[AppColorsKey.self] = .light
        t[AppTypographyKey.self] = .default
        t[AppSpacingKey.self] = .default
        t[AppBordersKey.self] = .default
        return t
    }()
}
