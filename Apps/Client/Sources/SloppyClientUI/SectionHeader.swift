import AdaEngine

public struct SectionHeader: View {
    let title: String
    let accentColor: Color

    public init(_ title: String, accentColor: Color = Theme.accent) {
        self.title = title
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: Theme.spacingS) {
            Color.clear
                .frame(width: Theme.borderThick, height: 24)
                .background(accentColor)

            Text(title.uppercased())
                .font(.system(size: Theme.fontHeading))
                .foregroundColor(Theme.textPrimary)

            Spacer()
        }
    }
}
