import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ChatTranscriptNativeItem: Identifiable, Equatable {
    enum Content: Equatable {
        case revealEarlier(count: Int)
        case dateSeparator(Date)
        case entry(
            ChatTranscriptEntry,
            bottomSpacing: CGFloat,
            activeMessageIDs: Set<ChatMessage.ID>,
            providerRecoveryMessageIDs: Set<ChatMessage.ID>
        )
        case changeSummary(ProjectWorkingTreeSourceControlResponse)
        case thinking(label: String, details: String?)
        case inputRequest(
            request: ChatPlanInputRequest,
            isSubmitting: Bool,
            errorMessage: String?
        )
    }

    let id: String
    let content: Content
}

@MainActor
struct ChatNativeTranscriptView: View {
    let items: [ChatTranscriptNativeItem]
    let contentWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollToEndRequest: Int
    let autoFollowAppendedItems: Bool
    let autoFollowChangingTail: Bool
    let scrollTarget: ChatTranscriptScrollTarget?
    let renderRevision: UInt
    let reduceMotion: Bool
    let onVisibleItemChange: @MainActor (String?) -> Void
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

    var body: some View {
        #if os(macOS)
        AppKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            autoFollowAppendedItems: autoFollowAppendedItems,
            autoFollowChangingTail: autoFollowChangingTail,
            scrollTarget: scrollTarget,
            renderRevision: renderRevision,
            reduceMotion: reduceMotion,
            onVisibleItemChange: onVisibleItemChange,
            renderer: renderer
        )
        #else
        UIKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            scrollTarget: scrollTarget,
            renderRevision: renderRevision,
            reduceMotion: reduceMotion,
            onVisibleItemChange: onVisibleItemChange,
            renderer: renderer
        )
        #endif
    }
}

#if canImport(UIKit) && !os(macOS)
private struct UIKitChatTranscriptCollection: UIViewRepresentable {
    let items: [ChatTranscriptNativeItem]
    let contentWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollToEndRequest: Int
    let scrollTarget: ChatTranscriptScrollTarget?
    let renderRevision: UInt
    let reduceMotion: Bool
    let onVisibleItemChange: @MainActor (String?) -> Void
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
                if didPrepend && !wasNearBottom {
                    let delta = collectionView.contentSize.height - oldContentHeight
                    let topInsetDelta = parent.topInset - oldTopInset
                    collectionView.contentOffset = CGPoint(
                        x: oldOffset.x,
                        y: oldOffset.y + delta + topInsetDelta
                    )
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

#if os(macOS)
struct AppKitChatTranscriptCollection: NSViewRepresentable {
    let items: [ChatTranscriptNativeItem]
    let contentWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollToEndRequest: Int
    let autoFollowAppendedItems: Bool
    let autoFollowChangingTail: Bool
    let scrollTarget: ChatTranscriptScrollTarget?
    let renderRevision: UInt
    let reduceMotion: Bool
    let onVisibleItemChange: @MainActor (String?) -> Void
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

    init(
        items: [ChatTranscriptNativeItem],
        contentWidth: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        scrollToEndRequest: Int,
        autoFollowAppendedItems: Bool = true,
        autoFollowChangingTail: Bool = true,
        scrollTarget: ChatTranscriptScrollTarget? = nil,
        renderRevision: UInt,
        reduceMotion: Bool,
        onVisibleItemChange: @escaping @MainActor (String?) -> Void = { _ in },
        renderer: @escaping @MainActor (ChatTranscriptNativeItem) -> AnyView
    ) {
        self.items = items
        self.contentWidth = contentWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.scrollToEndRequest = scrollToEndRequest
        self.autoFollowAppendedItems = autoFollowAppendedItems
        self.autoFollowChangingTail = autoFollowChangingTail
        self.scrollTarget = scrollTarget
        self.renderRevision = renderRevision
        self.reduceMotion = reduceMotion
        self.onVisibleItemChange = onVisibleItemChange
        self.renderer = renderer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(100)
            )
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            return NSCollectionLayoutSection(group: group)
        }
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(
            AppKitHostedTranscriptItem.self,
            forItemWithIdentifier: AppKitHostedTranscriptItem.identifier
        )

        let scrollView = AppKitChatTranscriptScrollView()
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateCollectionWidth()
        }

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        context.coordinator.installDataSource(on: collectionView)
        context.coordinator.startObservingScroll()
        context.coordinator.update(parent: self, initial: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self, initial: false)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingScroll()
        coordinator.dataSource = nil
        (scrollView as? AppKitChatTranscriptScrollView)?.onLayout = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AppKitChatTranscriptCollection
        weak var collectionView: NSCollectionView?
        weak var scrollView: NSScrollView?
        var dataSource: NSCollectionViewDiffableDataSource<Int, String>?
        private var itemByID: [String: ChatTranscriptNativeItem] = [:]
        private var previousItems: [ChatTranscriptNativeItem] = []
        private var previousContentWidth: CGFloat = 0
        private var previousViewportWidth: CGFloat = 0
        private var previousTopInset: CGFloat = 0
        private var previousBottomInset: CGFloat = 0
        private var previousScrollRequest: Int?
        private var previousScrollTarget: ChatTranscriptScrollTarget?
        private var scrollObserver: NSObjectProtocol?
        private var isNearBottom = true
        private var heightUpdateScheduled = false
        private var heightUpdateFollowsBottom = false
        private var parentUpdateGeneration: UInt = 0
        private var visibleItemID: String?

        private struct ViewportAnchor {
            let followsBottom: Bool
            let itemID: String?
            let itemOffset: CGFloat
            let fallbackOrigin: NSPoint
        }

        init(parent: AppKitChatTranscriptCollection) {
            self.parent = parent
        }

        func installDataSource(on collectionView: NSCollectionView) {
            dataSource = NSCollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) {
                [weak self] collectionView, indexPath, itemID in
                guard let self,
                      let item = self.itemByID[itemID],
                      let hostedItem = collectionView.makeItem(
                        withIdentifier: AppKitHostedTranscriptItem.identifier,
                        for: indexPath
                      ) as? AppKitHostedTranscriptItem else {
                    return nil
                }
                self.configure(hostedItem, with: item)
                return hostedItem
            }
        }

        private func configure(_ hostedItem: AppKitHostedTranscriptItem, with item: ChatTranscriptNativeItem) {
            hostedItem.onHeightChange = { [weak self] in
                self?.scheduleHeightUpdate(for: item.id)
            }
            hostedItem.configure(
                rootView: AnyView(
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        parent.renderer(item)
                            .frame(width: parent.contentWidth)
                        Spacer(minLength: 0)
                    }
                    .id(item.id)
                    .frame(width: max(scrollView?.contentSize.width ?? parent.contentWidth, 1))
                    .fixedSize(horizontal: false, vertical: true)
                ),
                measurementKey: item.id
            )
        }

        private func trailingContentItem(in items: [ChatTranscriptNativeItem]) -> ChatTranscriptNativeItem? {
            items.last { item in
                if case .entry = item.content { return true }
                return false
            } ?? items.last
        }

        private func scheduleHeightUpdate(for itemID: String) {
            let followsChangingTail = parent.autoFollowChangingTail
                && trailingContentItem(in: parent.items)?.id == itemID
            heightUpdateFollowsBottom = heightUpdateFollowsBottom
                || (followsChangingTail && isNearBottom)
            guard !heightUpdateScheduled else { return }
            heightUpdateScheduled = true
            let viewportAnchor = captureViewportAnchor(followsBottom: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let followsBottom = self.heightUpdateFollowsBottom
                self.heightUpdateFollowsBottom = false
                self.heightUpdateScheduled = false
                self.collectionView?.collectionViewLayout?.invalidateLayout()
                self.collectionView?.layoutSubtreeIfNeeded()
                if followsBottom {
                    self.scrollToBottom(animated: false)
                } else {
                    self.restoreViewport(viewportAnchor)
                }
                self.updateNearBottom()
                self.updateVisibleItem()
            }
        }

        func startObservingScroll() {
            guard let scrollView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateNearBottom()
                    self?.updateVisibleItem()
                }
            }
        }

        func stopObservingScroll() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
        }

        func update(parent: AppKitChatTranscriptCollection, initial: Bool) {
            guard let collectionView, let scrollView else { return }
            let explicitScroll = previousScrollRequest != parent.scrollToEndRequest
            let targetedScroll = previousScrollTarget != parent.scrollTarget
            let widthChanged = abs(previousContentWidth - parent.contentWidth) > 0.5
            let bottomInsetChanged = abs(previousBottomInset - parent.bottomInset) > 0.5
            let identitiesChanged = previousItems.map(\.id) != parent.items.map(\.id)
            let oldByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
            let changedIDs = parent.items.compactMap { item -> String? in
                guard oldByID[item.id] != item || widthChanged else { return nil }
                return item.id
            }
            let visibleChangedIDs = changedIDs.filter { id in
                guard let indexPath = dataSource?.indexPath(for: id) else { return false }
                return collectionView.item(at: indexPath) != nil
            }
            let oldTail = trailingContentItem(in: previousItems)
            let newTail = trailingContentItem(in: parent.items)
            let appendedContent: Bool
            if let oldTail, let newTail,
               let oldIndex = parent.items.firstIndex(where: { $0.id == oldTail.id }),
               let newIndex = parent.items.firstIndex(where: { $0.id == newTail.id }) {
                appendedContent = newIndex > oldIndex
            } else {
                appendedContent = false
            }
            let appendedLastItem = previousItems.last.map { last in
                parent.items.last?.id != last.id
                    && parent.items.contains(where: { $0.id == last.id })
            } ?? false
            let changedTail = newTail.flatMap { item in
                oldByID[item.id].map { $0 != item }
            } ?? false
            let oldEntryIDs = previousItems.compactMap { item -> String? in
                if case .entry = item.content { return item.id }
                return nil
            }
            let newEntryIDs = parent.items.compactMap { item -> String? in
                if case .entry = item.content { return item.id }
                return nil
            }
            let replacedTail = !oldEntryIDs.isEmpty
                && oldEntryIDs.count == newEntryIDs.count
                && oldEntryIDs.last != newEntryIDs.last
                && oldEntryIDs.dropLast().elementsEqual(newEntryIDs.dropLast())
            let followsExistingTail = parent.autoFollowChangingTail
                && ((changedTail && !widthChanged) || replacedTail)
            let followsBottom = ((appendedContent || appendedLastItem) && parent.autoFollowAppendedItems)
                || followsExistingTail
            let requiresViewportUpdate = initial
                || targetedScroll
                || explicitScroll
                || bottomInsetChanged
                || widthChanged
                || identitiesChanged
                || !visibleChangedIDs.isEmpty
            let viewportAnchor = requiresViewportUpdate
                ? captureViewportAnchor(followsBottom: followsBottom)
                : nil

            self.parent = parent
            itemByID = Dictionary(uniqueKeysWithValues: parent.items.map { ($0.id, $0) })
            scrollView.automaticallyAdjustsContentInsets = false
            if initial || previousTopInset != parent.topInset || bottomInsetChanged {
                scrollView.contentInsets = NSEdgeInsets(
                    top: parent.topInset,
                    left: 0,
                    bottom: parent.bottomInset,
                    right: 0
                )
            }
            updateCollectionWidth()

            if initial || identitiesChanged {
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(parent.items.map(\.id), toSection: 0)
                snapshot.reloadItems(changedIDs.filter { oldByID[$0] != nil })
                dataSource?.apply(snapshot, animatingDifferences: false)
            } else if !changedIDs.isEmpty {
                // Keep the hosting view and its local state alive during streaming.
                for id in visibleChangedIDs {
                    guard let indexPath = dataSource?.indexPath(for: id),
                          let hostedItem = collectionView.item(at: indexPath) as? AppKitHostedTranscriptItem,
                          let item = itemByID[id] else { continue }
                    configure(hostedItem, with: item)
                }
                if !visibleChangedIDs.isEmpty {
                    collectionView.collectionViewLayout?.invalidateLayout()
                }
            }

            if let viewportAnchor {
                parentUpdateGeneration &+= 1
                let generation = parentUpdateGeneration
                DispatchQueue.main.async { [weak self, weak collectionView] in
                    guard let self, let collectionView,
                          self.parentUpdateGeneration == generation else { return }
                    collectionView.layoutSubtreeIfNeeded()
                    if targetedScroll, let target = parent.scrollTarget {
                        self.scroll(to: target.itemID, animated: !parent.reduceMotion)
                    } else if explicitScroll || initial {
                        self.scrollToBottom(animated: explicitScroll && !parent.reduceMotion)
                    } else {
                        self.restoreViewport(viewportAnchor)
                    }
                    self.updateNearBottom()
                    self.updateVisibleItem()
                }
            }

            previousItems = parent.items
            previousContentWidth = parent.contentWidth
            previousTopInset = parent.topInset
            previousBottomInset = parent.bottomInset
            previousScrollRequest = parent.scrollToEndRequest
            previousScrollTarget = parent.scrollTarget
        }

        func updateCollectionWidth() {
            guard let collectionView, let scrollView,
                  let layout = collectionView.collectionViewLayout else { return }
            let width = max(scrollView.contentSize.width, 1)
            guard abs(previousViewportWidth - width) > 0.5 else { return }
            previousViewportWidth = width
            collectionView.setFrameSize(NSSize(width: width, height: collectionView.frame.height))
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard let id = dataSource?.itemIdentifier(for: indexPath),
                      let item = itemByID[id],
                      let hostedItem = collectionView.item(at: indexPath) as? AppKitHostedTranscriptItem else { continue }
                configure(hostedItem, with: item)
            }
            layout.invalidateLayout()
        }

        private func captureViewportAnchor(followsBottom: Bool) -> ViewportAnchor {
            guard let collectionView, let scrollView else {
                return ViewportAnchor(
                    followsBottom: true,
                    itemID: nil,
                    itemOffset: 0,
                    fallbackOrigin: .zero
                )
            }
            let bounds = scrollView.contentView.bounds
            let anchor = collectionView.indexPathsForVisibleItems().compactMap {
                indexPath -> (id: String, frame: NSRect)? in
                guard let id = dataSource?.itemIdentifier(for: indexPath),
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                    return nil
                }
                return (id, attributes.frame)
            }.filter { candidate in
                candidate.frame.maxY >= bounds.minY - 0.5
            }.min { lhs, rhs in
                lhs.frame.minY < rhs.frame.minY
            }
            return ViewportAnchor(
                followsBottom: isNearBottom && followsBottom,
                itemID: anchor?.id,
                itemOffset: (anchor?.frame.minY ?? bounds.minY) - bounds.minY,
                fallbackOrigin: bounds.origin
            )
        }

        private func restoreViewport(_ anchor: ViewportAnchor) {
            guard let collectionView, let scrollView else { return }
            if anchor.followsBottom {
                scrollToBottom(animated: false)
                return
            }

            var origin = anchor.fallbackOrigin
            if let itemID = anchor.itemID,
               let indexPath = dataSource?.indexPath(for: itemID),
               let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                origin.y = attributes.frame.minY - anchor.itemOffset
            }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func updateNearBottom() {
            guard let collectionView, let scrollView else {
                isNearBottom = true
                return
            }
            let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
            let visibleBottom = scrollView.contentView.bounds.maxY
            isNearBottom = contentHeight <= scrollView.contentView.bounds.height
                || visibleBottom >= contentHeight + parent.bottomInset - 44
        }

        private func scrollToBottom(animated: Bool) {
            guard let collectionView, !parent.items.isEmpty else { return }
            let indexPath = IndexPath(item: parent.items.count - 1, section: 0)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    collectionView.animator().scrollToItems(at: [indexPath], scrollPosition: .bottom)
                }
            } else {
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .bottom)
            }
        }

        private func scroll(to itemID: String, animated: Bool) {
            guard let collectionView,
                  let indexPath = dataSource?.indexPath(for: itemID) else { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    collectionView.animator().scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
                }
            } else {
                collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
            }
        }

        private func updateVisibleItem() {
            guard let collectionView, let scrollView else { return }
            let focusY = scrollView.contentView.bounds.minY
                + min(scrollView.contentView.bounds.height * 0.25, 120)
            let visible = collectionView.indexPathsForVisibleItems().compactMap { indexPath -> (String, CGFloat)? in
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

@MainActor
private final class AppKitChatTranscriptScrollView: NSScrollView {
    var onLayout: (@MainActor () -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

@MainActor
final class AppKitHostedTranscriptItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("chat.native-transcript.hosted-item")
    private var hostingView: NSHostingView<AnyView>?
    private var hostingConstraints: [NSLayoutConstraint] = []
    private var measuredHeight: CGFloat = 0
    private var measurementKey: String?
    private var measurementGeneration: UInt = 0
    private var needsSynchronousMeasurement = true
    private(set) var synchronousMeasurementPasses = 0
    var onHeightChange: (@MainActor () -> Void)?

    override func loadView() {
        view = NSView()
    }

    func configure(rootView: AnyView, measurementKey: String? = nil) {
        let changedItem = measurementKey != nil && measurementKey != self.measurementKey
        if measurementKey == nil || measurementKey != self.measurementKey {
            self.measurementKey = measurementKey
            measuredHeight = 0
            needsSynchronousMeasurement = true
        }
        measurementGeneration &+= 1
        let generation = measurementGeneration
        let measuredRoot = AnyView(rootView.onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
        } action: { [weak self] height in
            guard let self, self.measurementGeneration == generation,
                  height.isFinite, height > 0 else { return }
            self.needsSynchronousMeasurement = false
            guard abs(self.measuredHeight - height) > 0.5 else { return }
            self.measuredHeight = height
            // Geometry callbacks run inside SwiftUI layout; invalidate on the next turn.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.measurementGeneration == generation else { return }
                if let onHeightChange = self.onHeightChange {
                    onHeightChange()
                } else {
                    self.collectionView?.collectionViewLayout?.invalidateLayout()
                }
            }
        })
        if let hostingView, !changedItem {
            hostingView.rootView = measuredRoot
            return
        }
        if let hostingView {
            NSLayoutConstraint.deactivate(hostingConstraints)
            hostingView.removeFromSuperview()
        }
        let hostingView = NSHostingView(rootView: measuredRoot)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        hostingConstraints = [
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(hostingConstraints)
        self.hostingView = hostingView
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? NSCollectionViewLayoutAttributes else {
            return layoutAttributes
        }
        if !needsSynchronousMeasurement, measuredHeight > 0 {
            attributes.size.height = measuredHeight
            return attributes
        }
        guard let hostingView else { return layoutAttributes }
        synchronousMeasurementPasses += 1
        hostingView.layoutSubtreeIfNeeded()
        let height = ceil(hostingView.fittingSize.height)
        if height.isFinite && height > 0 {
            measuredHeight = height
            needsSynchronousMeasurement = false
            attributes.size.height = height
        }
        return attributes
    }
}
#endif
