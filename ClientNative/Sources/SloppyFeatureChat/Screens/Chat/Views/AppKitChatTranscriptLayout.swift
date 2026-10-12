import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if os(macOS)
// A single transcript column does not need estimated compositional groups.
// Rebuild inexpensive row positions from cached heights, rather than resetting
// already measured rows to estimates and asking their SwiftUI subtrees to fit again.
@MainActor
class AppKitChatTranscriptLayout: NSCollectionViewLayout {
    var heightForItem: (@MainActor (IndexPath) -> CGFloat?)?
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize: NSSize = .zero
    private var preferredInvalidationCounts: [IndexPath: Int] = [:]
    private static let maxConsecutivePreferredInvalidations = 3

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        if abs(collectionView.bounds.width - contentSize.width) > 0.5 {
            preferredInvalidationCounts.removeAll()
        }
        let width = max(collectionView.bounds.width, 1)
        var originY: CGFloat = 0
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        attributes = (0..<count).map { index in
            let indexPath = IndexPath(item: index, section: 0)
            let height = heightForItem?(indexPath) ?? 100
            let item = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            item.frame = NSRect(x: 0, y: originY, width: width, height: height)
            originY += height
            return item
        }
        contentSize = NSSize(width: width, height: originY)
    }

    override var collectionViewContentSize: NSSize { contentSize }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - contentSize.width) > 0.5
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes
    ) -> Bool {
        guard let indexPath = preferredAttributes.indexPath else { return false }
        guard abs(preferredAttributes.size.height - originalAttributes.size.height) > 0.5 else {
            preferredInvalidationCounts[indexPath] = nil
            return false
        }
        // prepare() takes heights from heightForItem, which can disagree with the
        // row's own measurement. Without a limit AppKit re-enters
        // _updateVisibleCellsNow until it hits its recursion assertion.
        let count = preferredInvalidationCounts[indexPath, default: 0] + 1
        guard count <= Self.maxConsecutivePreferredInvalidations else { return false }
        preferredInvalidationCounts[indexPath] = count
        return true
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutInvalidationContext {
        let context = NSCollectionViewLayoutInvalidationContext()
        // A height change also moves the rows below it, but their measurements
        // remain valid and come from heightForItem when preparing the new frames.
        guard let indexPath = preferredAttributes.indexPath else { return context }
        let index = indexPath.item
        guard index < attributes.count else {
            context.invalidateItems(at: [indexPath])
            return context
        }
        context.invalidateItems(at: Set((index..<attributes.count).map {
            IndexPath(item: $0, section: 0)
        }))
        return context
    }
}
#endif
