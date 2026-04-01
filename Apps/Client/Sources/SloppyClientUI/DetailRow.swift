import AdaEngine

public struct DetailRow: View {
    let label: String
    let value: String

    @Environment(\.theme) private var theme

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(spacing: 0) {
            HStack(spacing: sp.s) {
                Text(label.uppercased())
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)
                Spacer()
                Text(value)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textPrimary)
            }
            .padding(.vertical, sp.s)
            .padding(.horizontal, sp.m)

            Color.clear
                .frame(height: bo.thin)
                .background(c.border)
        }
    }
}
