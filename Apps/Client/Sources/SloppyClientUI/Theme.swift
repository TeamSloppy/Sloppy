import AdaEngine

public enum Theme {

    // MARK: - Backgrounds

    public static let bg = Color.fromHex(0x0A0A0A)
    public static let surface = Color.fromHex(0x141414)
    public static let surfaceRaised = Color.fromHex(0x1C1C1C)

    // MARK: - Accents

    public static let accent = Color.fromHex(0xFF2D6F)
    public static let accentCyan = Color.fromHex(0x00F0FF)
    public static let accentAcid = Color.fromHex(0xCDFF00)

    // MARK: - Text

    public static let textPrimary = Color.fromHex(0xF0F0F0)
    public static let textSecondary = Color.fromHex(0x777777)
    public static let textMuted = Color.fromHex(0x4A4A4A)

    // MARK: - Borders

    public static let border = Color.fromHex(0x2A2A2A)
    public static let borderBold = Color.fromHex(0x444444)

    // MARK: - Status

    public static let statusActive = Color.fromHex(0x00F0FF)
    public static let statusReady = Color.fromHex(0xCDFF00)
    public static let statusDone = Color.fromHex(0x4ADE80)
    public static let statusBlocked = Color.fromHex(0xFF3333)
    public static let statusWarning = Color.fromHex(0xFFAA00)
    public static let statusNeutral = Color.fromHex(0x666666)

    // MARK: - Typography sizes

    public static let fontHero: Double = 42
    public static let fontTitle: Double = 28
    public static let fontHeading: Double = 20
    public static let fontBody: Double = 15
    public static let fontCaption: Double = 12
    public static let fontMicro: Double = 10

    // MARK: - Spacing

    public static let spacingXS: Float = 4
    public static let spacingS: Float = 8
    public static let spacingM: Float = 16
    public static let spacingL: Float = 24
    public static let spacingXL: Float = 32
    public static let spacingXXL: Float = 48

    // MARK: - Borders

    public static let borderThin: Float = 1
    public static let borderMedium: Float = 2
    public static let borderThick: Float = 3
}
