import AdaEngine

public struct DetailRow: View {
    let label: String
    let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.spacingS) {
                Text(label.uppercased())
                    .font(.system(size: Theme.fontMicro))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Text(value)
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(.vertical, Theme.spacingS)
            .padding(.horizontal, Theme.spacingM)

            Color.clear
                .frame(height: Theme.borderThin)
                .background(Theme.border)
        }
    }
}
