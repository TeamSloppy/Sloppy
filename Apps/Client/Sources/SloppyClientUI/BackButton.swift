import AdaEngine

public struct BackButton: View {
    let label: String
    let action: () -> Void

    public init(_ label: String = "Back", action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingXS) {
                Text("<")
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.accent)
                Text(label.uppercased())
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, Theme.spacingS)
            .padding(.vertical, Theme.spacingXS)
            .border(Theme.accent, lineWidth: Theme.borderThin)
        }
    }
}
