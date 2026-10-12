import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit) && !os(macOS)
struct UIKitChatTranscriptCollection: UIViewRepresentable {
    let items: [ChatTranscriptNativeItem]
    let contentWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollToEndRequest: Int
    let scrollTarget: ChatTranscriptScrollTarget?
    let renderRevision: UInt
    let reduceMotion: Bool
    let onVisibleItemChange: @MainActor (String?) -> Void
    let onReachedTop: @MainActor () -> Void
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

    init(
        items: [ChatTranscriptNativeItem],
        contentWidth: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        scrollToEndRequest: Int,
        scrollTarget: ChatTranscriptScrollTarget? = nil,
        renderRevision: UInt,
        reduceMotion: Bool,
        onVisibleItemChange: @escaping @MainActor (String?) -> Void = { _ in },
        onReachedTop: @escaping @MainActor () -> Void = {},
        renderer: @escaping @MainActor (ChatTranscriptNativeItem) -> AnyView
    ) {
        self.items = items
        self.contentWidth = contentWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.scrollToEndRequest = scrollToEndRequest
        self.scrollTarget = scrollTarget
        self.renderRevision = renderRevision
        self.reduceMotion = reduceMotion
        self.onVisibleItemChange = onVisibleItemChange
        self.onReachedTop = onReachedTop
        self.renderer = renderer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(100)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            return NSCollectionLayoutSection(group: group)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        #if !os(visionOS)
        collectionView.keyboardDismissMode = .interactive
        #endif
        collectionView.showsVerticalScrollIndicator = true
        collectionView.delegate = context.coordinator
        context.coordinator.installDataSource(on: collectionView)
        context.coordinator.update(parent: self, collectionView: collectionView, initial: true)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.update(parent: self, collectionView: collectionView, initial: false)
    }

    static func dismantleUIView(_ collectionView: UICollectionView, coordinator: Coordinator) {
        collectionView.delegate = nil
        coordinator.dataSource = nil
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: UIKitChatTranscriptCollection
        var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var itemByID: [String: ChatTranscriptNativeItem] = [:]
        private var previousItems: [ChatTranscriptNativeItem] = []
        private var previousContentWidth: CGFloat = 0
        private var previousTopInset: CGFloat = 0
        private var previousBottomInset: CGFloat = 0
        private var previousScrollRequest: Int?
        private var previousScrollTarget: ChatTranscriptScrollTarget?
        private var previousRenderRevision: UInt?
        private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, String>?
        private var visibleItemID: String?
        private var historyScrollTrigger = ChatHistoryScrollTrigger()

        init(parent: UIKitChatTranscriptCollection) {
            self.parent = parent
        }

        func installDataSource(on collectionView: UICollectionView) {
            let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> {
                [weak self] cell, _, itemID in
                guard let self, let item = self.itemByID[itemID] else { return }
                cell.backgroundColor = .clear
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        self.parent.renderer(item)
                            .frame(width: self.parent.contentWidth)
                        Spacer(minLength: 0)
                    }
                }
                .margins(.all, 0)
            }
            cellRegistration = registration
            dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) {
                collectionView, indexPath, itemID in
                collectionView.dequeueConfiguredReusableCell(
                    using: registration,
                    for: indexPath,
                    item: itemID
                )
            }
        }

        func update(
            parent: UIKitChatTranscriptCollection,
            collectionView: UICollectionView,
            initial: Bool
        ) {
            let wasNearBottom = isNearBottom(collectionView)
            let oldContentHeight = collectionView.contentSize.height
            let oldOffset = collectionView.contentOffset
            let oldTopInset = previousTopInset
            let viewportAnchor = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> (id: String, offset: CGFloat, y: CGFloat)? in
                guard let id = dataSource?.itemIdentifier(for: indexPath), id.hasPrefix("entry:"),
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
                return (id, attributes.frame.minY - oldOffset.y, attributes.frame.minY)
            }.min { $0.y < $1.y }
            let didPrepend = didPrependItems(from: previousItems, to: parent.items)
            let explicitScroll = previousScrollRequest != parent.scrollToEndRequest
            let targetedScroll = previousScrollTarget != parent.scrollTarget
            let contentChanged = previousRenderRevision != parent.renderRevision
            let widthChanged = abs(previousContentWidth - parent.contentWidth) > 0.5
            let bottomInsetChanged = abs(previousBottomInset - parent.bottomInset) > 0.5

            self.parent = parent
            itemByID = Dictionary(uniqueKeysWithValues: parent.items.map { ($0.id, $0) })
            collectionView.contentInset = UIEdgeInsets(
                top: parent.topInset,
                left: 0,
                bottom: parent.bottomInset,
                right: 0
            )
            collectionView.verticalScrollIndicatorInsets = collectionView.contentInset

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(parent.items.map(\.id), toSection: 0)
            if !initial {
                let oldByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
                let changedIDs = parent.items.compactMap { item -> String? in
                    guard let oldItem = oldByID[item.id], oldItem != item else { return nil }
                    return item.id
                }
                var reloadableIDs = Set(changedIDs.filter { snapshot.indexOfItem($0) != nil })
                if widthChanged {
                    reloadableIDs.formUnion(parent.items.map(\.id))
                }
                if !reloadableIDs.isEmpty {
                    snapshot.reconfigureItems(Array(reloadableIDs))
                }
            }

            dataSource?.apply(snapshot, animatingDifferences: false) { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                collectionView.layoutIfNeeded()
                if didPrepend {
                    if let viewportAnchor,
                       let indexPath = self.dataSource?.indexPath(for: viewportAnchor.id),
                       let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                        collectionView.contentOffset = CGPoint(x: oldOffset.x, y: attributes.frame.minY - viewportAnchor.offset)
                    } else {
                        let delta = collectionView.contentSize.height - oldContentHeight
                        let topInsetDelta = parent.topInset - oldTopInset
                        collectionView.contentOffset = CGPoint(x: oldOffset.x, y: oldOffset.y + delta + topInsetDelta)
                    }
                } else if targetedScroll, let target = parent.scrollTarget {
                    self.scroll(to: target.itemID, in: collectionView, animated: !parent.reduceMotion)
                } else if explicitScroll || (wasNearBottom && (contentChanged || bottomInsetChanged)) || initial {
                    self.scrollToBottom(
                        collectionView,
                        animated: explicitScroll && !initial && !parent.reduceMotion
                    )
                }
                self.updateVisibleItem(in: collectionView)
            }

            previousItems = parent.items
            previousContentWidth = parent.contentWidth
            previousTopInset = parent.topInset
            previousBottomInset = parent.bottomInset
            previousScrollRequest = parent.scrollToEndRequest
            previousScrollTarget = parent.scrollTarget
            previousRenderRevision = parent.renderRevision
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            updateVisibleItem(in: collectionView)
            if historyScrollTrigger.didScroll(
                distanceFromTop: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
                isUserInitiated: scrollView.isDragging || scrollView.isDecelerating
            ) {
                parent.onReachedTop()
            }
        }

        private func didPrependItems(
            from oldItems: [ChatTranscriptNativeItem],
            to newItems: [ChatTranscriptNativeItem]
        ) -> Bool {
            guard let oldFirst = oldItems.first(where: { $0.id.hasPrefix("entry:") }),
                  let oldIndex = oldItems.firstIndex(where: { $0.id == oldFirst.id }),
                  let newIndex = newItems.firstIndex(where: { $0.id == oldFirst.id }) else {
                return false
            }
            return newIndex > oldIndex
        }

        private func isNearBottom(_ collectionView: UICollectionView) -> Bool {
            guard collectionView.contentSize.height > 0 else { return true }
            let visibleBottom = collectionView.contentOffset.y + collectionView.bounds.height
            let contentBottom = collectionView.contentSize.height + collectionView.adjustedContentInset.bottom
            return visibleBottom >= contentBottom - 44
        }

        private func scrollToBottom(_ collectionView: UICollectionView, animated: Bool) {
            collectionView.layoutIfNeeded()
            let y = max(
                -collectionView.adjustedContentInset.top,
                collectionView.contentSize.height
                    - collectionView.bounds.height
                    + collectionView.adjustedContentInset.bottom
            )
            collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
        }

        private func scroll(to itemID: String, in collectionView: UICollectionView, animated: Bool) {
            guard let indexPath = dataSource?.indexPath(for: itemID) else { return }
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        }

        private func updateVisibleItem(in collectionView: UICollectionView) {
            let focusY = collectionView.contentOffset.y + min(collectionView.bounds.height * 0.25, 120)
            let visible = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> (String, CGFloat)? in
                guard let itemID = dataSource?.itemIdentifier(for: indexPath),
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
                return (itemID, abs(attributes.frame.midY - focusY))
            }
            let nextID = visible.min { $0.1 < $1.1 }?.0
            guard nextID != visibleItemID else { return }
            visibleItemID = nextID
            parent.onVisibleItemChange(nextID)
        }
    }
}
#endif
