import AdaEngine
import SloppyClientCore

public struct ScrollableTabViewStyle: TabViewStyle {
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
                                .foregroundColor(tab.isSelected ? Color.white : Color(0.6, 0.6, 0.6, 1.0))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tab.isSelected ? Color(0.2, 0.2, 0.2, 1.0) : Color.clear)
                        .border(tab.isSelected ? Color(0.3, 0.3, 0.3, 1.0) : Color.clear, lineWidth: 1)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 8)
            
            Color(0.2, 0.2, 0.2, 1.0)
                .frame(height: 1)

            configuration.content
        }
    }
}