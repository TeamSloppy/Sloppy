import AdaEngine

public struct AppAtmosphericBackground: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        let c = theme.colors

        return ZStack {
            c.background
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
