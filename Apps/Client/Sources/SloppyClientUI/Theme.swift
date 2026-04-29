import AdaEngine

// MARK: - AppColors

public struct AppColors: Sendable, Hashable {
    public var background: Color
    public var surface: Color
    public var surfaceRaised: Color

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
        background:     .fromHex(0x0A0A0A),
        surface:        .fromHex(0x141414),
        surfaceRaised:  .fromHex(0x1C1C1C),
        accent:         .fromHex(0xFF2D6F),
        accentCyan:     .fromHex(0x00F0FF),
        accentAcid:     .fromHex(0xCDFF00),
        textPrimary:    .fromHex(0xF2F2F2),
        textSecondary:  .fromHex(0xB7B7B7),
        textMuted:      .fromHex(0x707070),
        border:         .fromHex(0x2A2A2A),
        borderBold:     .fromHex(0x444444),
        statusActive:   .fromHex(0x00F0FF),
        statusReady:    .fromHex(0xCDFF00),
        statusDone:     .fromHex(0x4ADE80),
        statusBlocked:  .fromHex(0xFF3333),
        statusWarning:  .fromHex(0xFFAA00),
        statusNeutral:  .fromHex(0x666666)
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
        hero:    42,
        title:   28,
        heading: 20,
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
}
