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
        background:     .fromHex(0x191919),
        surface:        .fromHex(0x151515),
        surfaceRaised:  .fromHex(0x2B2B2B),
        surfaceGlass:   .fromHex(0x151515),
        surfaceGlow:    .fromHex(0x343434),
        accent:         .fromHex(0xE8E7E3),
        accentCyan:     .fromHex(0x00B8EE),
        accentAcid:     .fromHex(0xE7B99B),
        textPrimary:    .fromHex(0xF5F2E9),
        textSecondary:  .fromHex(0xBCBCBA),
        textMuted:      .fromHex(0x92928F),
        border:         .fromHex(0x343434),
        borderBold:     .fromHex(0x565656),
        statusActive:   .fromHex(0xE8E7E3),
        statusReady:    .fromHex(0xBCBCBA),
        statusDone:     .fromHex(0x50D69C),
        statusBlocked:  .fromHex(0xF2A18C),
        statusWarning:  .fromHex(0xE7B99B),
        statusNeutral:  .fromHex(0x92928F)
    )

    public static let light = AppColors(
        background:     .fromHex(0xF5F2E9),
        surface:        .fromHex(0xECEEE4),
        surfaceRaised:  .fromHex(0xC8E2AE),
        surfaceGlass:   .fromHex(0xF5F2E9),
        surfaceGlow:    .fromHex(0xD5D7CA),
        accent:         .fromHex(0x334D2B),
        accentCyan:     .fromHex(0x334D2B),
        accentAcid:     .fromHex(0x80532C),
        textPrimary:    .fromHex(0x242521),
        textSecondary:  .fromHex(0x4A5044),
        textMuted:      .fromHex(0x6D7066),
        border:         .fromHex(0xD5D7CA),
        borderBold:     .fromHex(0x9BBC80),
        statusActive:   .fromHex(0x334D2B),
        statusReady:    .fromHex(0x4A5044),
        statusDone:     .fromHex(0x334D2B),
        statusBlocked:  .fromHex(0xA13726),
        statusWarning:  .fromHex(0x80532C),
        statusNeutral:  .fromHex(0x6D7066)
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
