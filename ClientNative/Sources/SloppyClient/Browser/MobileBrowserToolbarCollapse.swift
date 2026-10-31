import Foundation
import Observation

struct BrowserScrollSample: Sendable {
    var offset: CGFloat
    var maximumOffset: CGFloat
    var viewportHeight: CGFloat
    var contentHeight: CGFloat
    var isUserScrolling: Bool
}

/// Scroll direction drives one bounded value; layout changes and rubber-banding do not.
@Observable
@MainActor
final class MobileBrowserToolbarCollapse {
    private(set) var progress: CGFloat = 0
    @ObservationIgnored private var previous: BrowserScrollSample?

    var isCollapsed: Bool { progress >= 0.5 }

    func expand() {
        progress = 0
        previous = nil
    }

    func consume(_ sample: BrowserScrollSample, transitionDistance: CGFloat) {
        guard sample.offset.isFinite, sample.maximumOffset.isFinite,
              sample.viewportHeight.isFinite, sample.contentHeight.isFinite else { return }
        var current = sample
        current.offset = min(max(0, sample.offset), max(0, sample.maximumOffset))
        defer { previous = current }
        if current.offset == 0 || current.maximumOffset <= 0 {
            progress = 0
            return
        }
        guard let previous, sample.isUserScrolling,
              abs(previous.viewportHeight - current.viewportHeight) < 1,
              abs(previous.contentHeight - current.contentHeight) < 1,
              transitionDistance.isFinite, transitionDistance > 0 else { return }
        let wasCollapsed = isCollapsed
        let next = progress + (current.offset - previous.offset) / transitionDistance
        progress = min(1, max(0, next))
        // Settle at an endpoint so tiny reversals cannot flicker between presentations.
        if isCollapsed != wasCollapsed { progress = isCollapsed ? 1 : 0 }
    }
}
