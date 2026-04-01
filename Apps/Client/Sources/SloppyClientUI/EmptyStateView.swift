import AdaEngine

public struct EmptyStateView: View {
    let text: String

    @Environment(\.theme) private var theme

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(spacing: sp.s) {
            Text("—")
                .font(.system(size: ty.title))
                .foregroundColor(c.textMuted)
            Text(text.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
        .padding(.vertical, sp.xl)
        .padding(.horizontal, sp.l)
        .border(c.border, lineWidth: bo.thin)
    }
}
