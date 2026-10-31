import Foundation

enum BrowserTabSwipeTarget: Equatable, Sendable {
    case existing(UUID)
    case newTab(UUID)

    var id: UUID {
        switch self {
        case .existing(let id), .newTab(let id): id
        }
    }
}

enum MobileBrowserPageID: Hashable, Sendable {
    case home
    case tab(UUID)
}

/// One gesture keeps its source and destination stable until the animation finishes.
struct MobileBrowserTabSwipe {
    static let pageSpacing: CGFloat = 12
    let id = UUID()
    let sourceID: UUID?
    let newTabID = UUID()
    let width: CGFloat
    var direction: BrowserTabSwipeDirection
    var target: BrowserTabSwipeTarget?
    var offset: CGFloat = 0
    var isSettling = false

    static func dragDirection(horizontal: CGFloat, vertical: CGFloat) -> BrowserTabSwipeDirection? {
        guard horizontal.isFinite, vertical.isFinite,
              abs(horizontal) >= 8, abs(horizontal) > abs(vertical) * 1.5 else { return nil }
        return horizontal < 0 ? .next : .previous
    }

    var sourcePageID: MobileBrowserPageID { sourceID.map(MobileBrowserPageID.tab) ?? .home }
    var pageIDs: [MobileBrowserPageID] {
        [sourcePageID] + (target.map { [.tab($0.id)] } ?? [])
    }

    mutating func update(horizontal: CGFloat, target: BrowserTabSwipeTarget?) {
        guard !isSettling, horizontal.isFinite, width.isFinite, width > 0 else { return }
        direction = horizontal < 0 ? .next : .previous
        self.target = target
        let distance = min(abs(horizontal), width + Self.pageSpacing)
        offset = (horizontal < 0 ? -1 : 1) * distance * (target == nil ? 0.18 : 1)
    }

    func shouldCommit(predictedHorizontal: CGFloat) -> Bool {
        guard target != nil, width.isFinite, width > 0, predictedHorizontal.isFinite else { return false }
        let sign: CGFloat = direction == .next ? -1 : 1
        let distance = offset * sign
        let projected = predictedHorizontal * sign
        guard distance > 0, projected >= -44 else { return false }
        return distance >= max(44, min(180, width * 0.28)) || (distance >= 18 && projected >= width * 0.5)
    }

    func destinationOffset(committing: Bool) -> CGFloat {
        guard committing else { return 0 }
        return (direction == .next ? -1 : 1) * (width + Self.pageSpacing)
    }

    func offset(for pageID: MobileBrowserPageID) -> CGFloat {
        if pageID == sourcePageID { return offset }
        return offset + (direction == .next ? 1 : -1) * (width + Self.pageSpacing)
    }

    func addressOffset(for pageID: MobileBrowserPageID, bubbleWidth: CGFloat) -> CGFloat {
        guard bubbleWidth.isFinite, bubbleWidth > 0 else { return 0 }
        let distance = bubbleWidth + Self.pageSpacing
        let translation = min(abs(offset), distance) * (offset < 0 ? -1 : 1)
        if pageID == sourcePageID { return translation }
        return translation + (direction == .next ? 1 : -1) * distance
    }
}
