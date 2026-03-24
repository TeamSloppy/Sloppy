import AdaEngine

public struct EntityCard: View {
    let title: String
    let subtitle: String
    let trailing: String?
    let accentColor: Color
    let onTap: () -> Void

    public init(
        title: String,
        subtitle: String,
        trailing: String? = nil,
        accentColor: Color = Theme.accent,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.accentColor = accentColor
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Theme.borderThick)
                    .background(accentColor)

                HStack(spacing: Theme.spacingM) {
                    VStack(alignment: .leading, spacing: Theme.spacingXS) {
                        Text(title.uppercased())
                            .font(.system(size: Theme.fontBody))
                            .foregroundColor(Theme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: Theme.fontCaption))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    if let trailing {
                        Text(trailing.uppercased())
                            .font(.system(size: Theme.fontMicro))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .padding(Theme.spacingM)
            }
            .background(Theme.surface)
            .border(Theme.border, lineWidth: Theme.borderThin)
        }
    }
}
