import AdaEngine

public struct AppAtmosphericBackground: View {
    @Environment(\.theme) private var theme
    public init() {}

    public var body: some View {
        theme.colors.background.allowsHitTesting(false)
    }
}
