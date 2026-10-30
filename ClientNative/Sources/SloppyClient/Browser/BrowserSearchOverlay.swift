#if os(macOS)
import SwiftUI

@MainActor
struct BrowserSearchOverlay: View {
    let state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let top = max(24, geometry.size.height * 0.22)
            ZStack(alignment: .top) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { state.isSearchPresented = false }
                    .accessibilityHidden(true)
                BrowserSearchSheet(state: state, onAskAgent: onAskAgent,
                                   maximumResultsHeight: min(304, max(0, geometry.size.height - top - 136)))
                    .frame(width: min(680, max(0, geometry.size.width - 48)))
                    .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 14)
                    .padding(.top, top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
