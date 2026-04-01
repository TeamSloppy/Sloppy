import AdaEngine

public struct SectionHeader: View {
    let title: String
    let accentColor: Color?

    @Environment(\.theme) private var theme

    public init(_ title: String, accentColor: Color? = nil) {
        self.title = title
        self.accentColor = accentColor
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography
        let accent = accentColor ?? c.accent

        return HStack(spacing: sp.s) {
            Color.clear
                .frame(width: bo.thick, height: 24)
                .background(accent)

            Text(title.uppercased())
                .font(.system(size: ty.heading))
                .foregroundColor(c.textPrimary)

            Spacer()
        }
    }
}
