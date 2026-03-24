import AdaEngine

public struct NotificationBannerItem: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var message: String
    public var accentColor: Color

    public init(id: String, title: String, message: String, accentColor: Color) {
        self.id = id
        self.title = title
        self.message = message
        self.accentColor = accentColor
    }
}

public struct NotificationBanner: View {
    let item: NotificationBannerItem

    public init(item: NotificationBannerItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Theme.borderThick)
                .background(item.accentColor)

            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(item.title.uppercased())
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(item.accentColor)
                Text(item.message)
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(Theme.spacingM)

            Spacer()
        }
        .background(Theme.surface)
        .border(item.accentColor, lineWidth: Theme.borderThin)
    }
}
