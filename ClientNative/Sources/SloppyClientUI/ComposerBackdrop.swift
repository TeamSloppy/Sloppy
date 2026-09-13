import SwiftUI

public struct ComposerBackdrop: View {
    public let height: CGFloat

    @Environment(\.theme) private var theme

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: theme.colors.background.opacity(0 as Double), location: 0),
                .init(color: theme.colors.background.opacity(0.85 as Double), location: 0.45),
                .init(color: theme.colors.background, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
