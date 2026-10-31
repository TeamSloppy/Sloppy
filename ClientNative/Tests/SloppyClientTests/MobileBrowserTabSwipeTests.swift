import Foundation
import Testing
@testable import SloppyClient

@Suite("Interactive browser tab swipes")
struct MobileBrowserTabSwipeTests {
    @Test(arguments: [CGFloat(142), CGFloat(288)])
    func addressBubbleTracksTheFingerAndFinishesAlongsideThePage(bubbleWidth: CGFloat) {
        let source = UUID()
        let target = UUID()
        var swipe = MobileBrowserTabSwipe(sourceID: source, width: 400, direction: .next)
        swipe.update(horizontal: -60, target: .existing(target))
        #expect(swipe.addressOffset(for: .tab(source), bubbleWidth: bubbleWidth) == -60)
        #expect(swipe.addressOffset(for: .tab(target), bubbleWidth: bubbleWidth) == bubbleWidth + 12 - 60)

        swipe.offset = swipe.destinationOffset(committing: true)
        #expect(swipe.offset(for: .tab(target)) == 0)
        #expect(swipe.addressOffset(for: .tab(target), bubbleWidth: bubbleWidth) == 0)
        swipe.offset = swipe.destinationOffset(committing: false)
        #expect(swipe.addressOffset(for: .tab(source), bubbleWidth: bubbleWidth) == 0)
        #expect(swipe.addressOffset(for: .tab(target), bubbleWidth: bubbleWidth) == bubbleWidth + 12)
    }

    @Test func addressBubbleReversesDirectionWithoutOvershootingItsOwnWidth() {
        let source = UUID()
        let target = UUID()
        var swipe = MobileBrowserTabSwipe(sourceID: source, width: 400, direction: .previous)
        swipe.update(horizontal: 80, target: .existing(target))
        #expect(swipe.addressOffset(for: .tab(source), bubbleWidth: 142) == 80)
        #expect(swipe.addressOffset(for: .tab(target), bubbleWidth: 142) == -74)
        swipe.offset = swipe.destinationOffset(committing: true)
        #expect(swipe.addressOffset(for: .tab(source), bubbleWidth: 142) == 154)
        #expect(swipe.addressOffset(for: .tab(target), bubbleWidth: 142) == 0)
    }

    @Test func contentFollowsTheFingerAndTheNeighborRemainsOnePageAway() {
        let source = UUID()
        let target = UUID()
        var swipe = MobileBrowserTabSwipe(sourceID: source, width: 400, direction: .next)
        swipe.update(horizontal: -120, target: .existing(target))
        #expect(swipe.offset(for: .tab(source)) == -120)
        #expect(swipe.offset(for: .tab(target)) == 292)
        #expect(swipe.pageIDs == [.tab(source), .tab(target)])
        #expect(swipe.shouldCommit(predictedHorizontal: -120))
        swipe.offset = swipe.destinationOffset(committing: true)
        #expect(swipe.offset(for: .tab(target)) == 0)
    }

    @Test func shortDragCancelsButAFastFlickCommits() {
        var swipe = MobileBrowserTabSwipe(sourceID: UUID(), width: 400, direction: .next)
        swipe.update(horizontal: -32, target: .newTab(swipe.newTabID))
        #expect(!swipe.shouldCommit(predictedHorizontal: -40))
        #expect(swipe.shouldCommit(predictedHorizontal: -260))
        #expect(swipe.destinationOffset(committing: false) == 0)
        #expect(!swipe.shouldCommit(predictedHorizontal: 90))
    }

    @Test func firstTabResistsOverdragAndCannotCommitWithoutANeighbor() {
        var swipe = MobileBrowserTabSwipe(sourceID: UUID(), width: 400, direction: .previous)
        swipe.update(horizontal: 200, target: nil)
        #expect(swipe.offset == 36)
        #expect(!swipe.shouldCommit(predictedHorizontal: 500))
        #expect(swipe.pageIDs.count == 1)
    }

    @Test func reversingTheDragChangesThePreviewAndSettlingFreezesInput() {
        let source = UUID()
        let previous = UUID()
        var swipe = MobileBrowserTabSwipe(sourceID: source, width: 400, direction: .next)
        swipe.update(horizontal: -70, target: .newTab(swipe.newTabID))
        swipe.update(horizontal: 80, target: .existing(previous))
        #expect(swipe.direction == .previous)
        #expect(swipe.pageIDs == [.tab(source), .tab(previous)])
        #expect(swipe.offset(for: .tab(previous)) == -332)
        swipe.isSettling = true
        swipe.update(horizontal: -200, target: .newTab(swipe.newTabID))
        #expect(swipe.direction == .previous)
        #expect(swipe.offset == 80)
    }

    @Test func diagonalAndInvalidInputDoNotStartPaging() {
        #expect(MobileBrowserTabSwipe.dragDirection(horizontal: -20, vertical: 2) == .next)
        #expect(MobileBrowserTabSwipe.dragDirection(horizontal: 20, vertical: 2) == .previous)
        #expect(MobileBrowserTabSwipe.dragDirection(horizontal: 4, vertical: 0) == nil)
        #expect(MobileBrowserTabSwipe.dragDirection(horizontal: 20, vertical: 25) == nil)
        #expect(MobileBrowserTabSwipe.dragDirection(horizontal: .nan, vertical: 0) == nil)
    }
}
