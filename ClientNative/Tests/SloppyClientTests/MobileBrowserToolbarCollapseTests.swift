import Foundation
import Testing
@testable import SloppyClient

@Suite("Mobile browser scrolling chrome")
@MainActor
struct MobileBrowserToolbarCollapseTests {
    private func sample(_ offset: CGFloat, user: Bool = true, viewport: CGFloat = 600,
                        content: CGFloat = 2000, maximum: CGFloat = 1400) -> BrowserScrollSample {
        .init(offset: offset, maximumOffset: maximum, viewportHeight: viewport,
              contentHeight: content, isUserScrolling: user)
    }

    @Test func scrollingDownCollapsesAndReversingRestoresControls() {
        let state = MobileBrowserToolbarCollapse()
        state.consume(sample(0, user: false), transitionDistance: 106)
        state.consume(sample(80), transitionDistance: 106)
        #expect(state.isCollapsed)
        state.consume(sample(60), transitionDistance: 106)
        #expect(state.isCollapsed) // Ignore a small reversal.
        state.consume(sample(20), transitionDistance: 106)
        #expect(!state.isCollapsed)
    }

    @Test func rubberBandingDoesNotReopenTheToolbarAtTheBottom() {
        let state = MobileBrowserToolbarCollapse()
        state.consume(sample(0, user: false), transitionDistance: 106)
        state.consume(sample(1400), transitionDistance: 106)
        #expect(state.isCollapsed)
        for offset: CGFloat in [1490, 1450, 1420, 1400] {
            state.consume(sample(offset), transitionDistance: 106)
            #expect(state.isCollapsed)
        }
    }

    @Test func pageScriptsAndViewportChangesDoNotToggleChrome() {
        let state = MobileBrowserToolbarCollapse()
        state.consume(sample(0, user: false), transitionDistance: 106)
        state.consume(sample(500, user: false), transitionDistance: 106)
        #expect(!state.isCollapsed)
        state.consume(sample(600), transitionDistance: 106)
        #expect(state.isCollapsed)
        state.consume(sample(520, viewport: 662), transitionDistance: 106)
        #expect(state.isCollapsed)
        state.consume(sample(450, viewport: 662, content: 3000), transitionDistance: 106)
        #expect(state.isCollapsed)
    }

    @Test func returningToTopOrOpeningControlsResetsTheScrollBaseline() {
        let state = MobileBrowserToolbarCollapse()
        state.consume(sample(0, user: false), transitionDistance: 106)
        state.consume(sample(300), transitionDistance: 106)
        state.consume(sample(-40), transitionDistance: 106)
        #expect(!state.isCollapsed)
        state.consume(sample(300), transitionDistance: 106)
        #expect(state.isCollapsed)
        state.expand()
        #expect(state.progress == 0)
        state.consume(sample(100, user: false), transitionDistance: 106)
        #expect(!state.isCollapsed)
    }

    @Test func shortPagesAlwaysKeepNavigationVisible() {
        let state = MobileBrowserToolbarCollapse()
        state.consume(sample(0, user: false), transitionDistance: 106)
        state.consume(sample(300), transitionDistance: 106)
        state.consume(sample(20, content: 200, maximum: 0), transitionDistance: 106)
        #expect(!state.isCollapsed)
    }
}
