#if os(macOS)
import SwiftUI

/// Keep floating controls consistent with the window's appearance, even when
/// the page below the transparent titlebar uses a different color scheme.
struct BrowserToolbarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
            } else {
                content
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .foregroundStyle(.primary)
        .tint(.primary)
    }
}
#endif
