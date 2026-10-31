#if os(iOS)
import SwiftUI
import SloppyClientUI

/// Stable page IDs keep the destination's WKWebView mounted when a swipe commits.
@MainActor
struct MobileBrowserPagePager: View {
    let state: BrowserWorkspaceState
    @Binding var swipe: MobileBrowserTabSwipe?
    @Binding var viewportWidth: CGFloat
    let onAskAgent: (String) -> Void
    let onHomeAskAgent: () -> Void
    var annotationTarget: BrowserTextAnnotationTarget?
    let onScroll: (UUID, BrowserScrollSample) -> Void
    @Environment(\.theme) private var theme

    private var selectedPageID: MobileBrowserPageID { state.selectedID.map(MobileBrowserPageID.tab) ?? .home }
    private var pageIDs: [MobileBrowserPageID] { swipe?.pageIDs ?? [selectedPageID] }
    private var isShowingHome: Bool { state.selectedTab?.url == nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pageIDs, id: \.self) { pageID in
                    page(for: pageID)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(background(for: pageID).ignoresSafeArea(.container, edges: .vertical))
                        .offset(x: swipe?.offset(for: pageID) ?? 0)
                        .allowsHitTesting(swipe == nil && pageID == selectedPageID)
                        .accessibilityHidden(swipe != nil || pageID != selectedPageID)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(theme.colors.background.ignoresSafeArea(.container, edges: .vertical))
            .overlay(alignment: .top) {
                if !isShowingHome {
                    MobileBrowserTopBackdrop(statusBarHeight: geometry.safeAreaInsets.top)
                }
            }
            .overlay(alignment: .top) {
                if let page = state.selectedPage, page.lastError != nil {
                    BrowserNavigationErrorBanner(page: page)
                        .padding(12)
                        .zIndex(1)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard width != viewportWidth else { return }
                viewportWidth = width
                swipe = nil
            }
        }
    }

    @ViewBuilder
    private func page(for pageID: MobileBrowserPageID) -> some View {
        if case .tab(let id) = pageID,
           let tab = state.tabs.first(where: { $0.id == id }), tab.url != nil,
           let page = state.pages[id] {
            BrowserWorkspacePage(page: page, restoredState: tab.interactionState,
                                 onAsk: onAskAgent, annotationTarget: annotationTarget,
                                 onScroll: { onScroll(id, $0) }, showsNavigationError: false)
                .id(ObjectIdentifier(page))
                .ignoresSafeArea(.container, edges: .vertical)
        } else {
            MobileBrowserHomeView(state: state,
                                  onSearch: { state.presentSearch(newTab: state.selectedID == nil) },
                                  onAskAgent: onHomeAskAgent)
                .padding(.top, pageID != selectedPageID && !isShowingHome ? 44 : 0)
        }
    }

    private func background(for pageID: MobileBrowserPageID) -> Color {
        if case .tab(let id) = pageID, state.tabs.first(where: { $0.id == id })?.url != nil {
            return Color(uiColor: state.pages[id]?.browserBackgroundColor ?? .systemBackground)
        }
        return theme.colors.background
    }
}
#endif
