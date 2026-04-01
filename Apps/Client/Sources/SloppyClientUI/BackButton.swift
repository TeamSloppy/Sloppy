import AdaEngine

public struct BackButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.theme) private var theme

    public init(_ label: String = "Back", action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return Button(action: action) {
            HStack(spacing: sp.xs) {
                Text("<")
                    .font(.system(size: ty.body))
                    .foregroundColor(c.accent)
                Text(label.uppercased())
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accent)
            }
            .padding(.horizontal, sp.s)
            .padding(.vertical, sp.xs)
            .border(c.accent, lineWidth: bo.thin)
        }
    }
}
