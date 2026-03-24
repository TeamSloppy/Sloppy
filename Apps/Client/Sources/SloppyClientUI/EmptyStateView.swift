import AdaEngine

public struct EmptyStateView: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(spacing: Theme.spacingS) {
            Text("—")
                .font(.system(size: Theme.fontTitle))
                .foregroundColor(Theme.textMuted)
            Text(text.uppercased())
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.vertical, Theme.spacingXL)
        .padding(.horizontal, Theme.spacingL)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}
