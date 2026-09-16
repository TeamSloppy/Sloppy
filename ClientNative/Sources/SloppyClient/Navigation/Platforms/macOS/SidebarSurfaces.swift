#if os(macOS)
import SwiftUI
import SloppyClientUI

struct SidebarScrollFade: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, value in
                isScrolled = value
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [theme.colors.background, theme.colors.background.opacity(0 as Double)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
                    .opacity(isScrolled ? 1.0 as Double : 0.0 as Double)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

struct SidebarFooterBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme.colors.background
            .ignoresSafeArea(edges: .bottom)
    }
}
#endif
