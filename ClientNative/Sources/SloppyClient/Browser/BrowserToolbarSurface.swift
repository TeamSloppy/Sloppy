#if os(macOS)
import SwiftUI

/// The page below the transparent titlebar need not follow the app's theme.
/// Keep each floating control's foreground and material in the same appearance.
struct BrowserToolbarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(.white, in: Capsule())
            } else {
                content
                    .background(.white.opacity(0.9), in: Capsule())
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .foregroundStyle(.black)
        .tint(.black)
        .environment(\.colorScheme, .light)
    }
}
#endif
