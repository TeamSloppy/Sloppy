import AdaEngine
import SloppyClientCore

public struct ScrollableTabViewStyle: TabViewStyle {
    @Environment(\.theme) private var theme
    public let accentColor: Color

    public init(accentColor: Color) {
        self.accentColor = accentColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(configuration.tabs) { tab in
                        Button {
                            tab.action()
                        } label: {
                            Text(tab.label ?? "TAB")
                                .font(.system(size: 14))
                                .foregroundColor(tab.isSelected ? theme.colors.textPrimary : theme.colors.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tab.isSelected ? theme.colors.surfaceRaised : Color.clear)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 8)
            
            theme.colors.border
                .frame(height: 1)

            configuration.content
        }
    }
}
