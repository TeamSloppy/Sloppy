import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
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
    let presentationRevision: UInt
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
        autoFollowAppendedItems: Bool = true,
        autoFollowChangingTail: Bool = true,
        scrollTarget: ChatTranscriptScrollTarget? = nil,
        renderRevision: UInt,
        presentationRevision: UInt = 0,
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
        self.autoFollowAppendedItems = autoFollowAppendedItems
        self.autoFollowChangingTail = autoFollowChangingTail
        self.scrollTarget = scrollTarget
        self.renderRevision = renderRevision
        self.presentationRevision = presentationRevision
        self.reduceMotion = reduceMotion
        self.onVisibleItemChange = onVisibleItemChange
        self.onReachedTop = onReachedTop
        self.renderer = renderer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = AppKitChatTranscriptLayout()
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
        private var previousPresentationRevision: UInt?
        private var previousContentWidth: CGFloat = 0
        private var previousViewportWidth: CGFloat = 0
        private var previousTopInset: CGFloat = 0
        private var previousBottomInset: CGFloat = 0
        private var previousScrollRequest: Int?
        private var previousScrollTarget: ChatTranscriptScrollTarget?
        private var scrollObserver: NSObjectProtocol?
        private var liveScrollObserver: NSObjectProtocol?
        private var isNearBottom = true
        private var previousLayoutHeight: CGFloat = 0
        private var pendingScrollToEnd = false
        private var scrollToEndScheduled = false
        private var heightUpdateScheduled = false
        private var heightUpdateFollowsBottom = false
        private var pendingHeightUpdateIDs: Set<String> = []
        private var measuredRows: [String: MeasuredRow] = [:]
        private var parentUpdateGeneration: UInt = 0
        private var visibleItemID: String?
        private var historyScrollTrigger = ChatHistoryScrollTrigger()
        private var isUserScrolling = false
        private var liveScrollEndObserver: NSObjectProtocol?

        private struct MeasuredRow {
            let item: ChatTranscriptNativeItem
            let contentWidth: CGFloat
            let height: CGFloat
        }

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
            (collectionView.collectionViewLayout as? AppKitChatTranscriptLayout)?.heightForItem = {
                [weak self] indexPath in
                guard let self,
                      let id = self.dataSource?.itemIdentifier(for: indexPath),
                      let item = self.itemByID[id] else { return nil }
                return self.cachedHeight(for: item) ?? self.measuredRows[id]?.height
            }
        }

        private func cachedHeight(for item: ChatTranscriptNativeItem) -> CGFloat? {
            guard let row = measuredRows[item.id], row.item == item,
                  abs(row.contentWidth - parent.contentWidth) <= 0.5 else {
                return nil
            }
            return row.height
        }

        private func configure(_ hostedItem: AppKitHostedTranscriptItem, with item: ChatTranscriptNativeItem) {
            let contentWidth = parent.contentWidth
            let viewportWidth = max(scrollView?.contentSize.width ?? contentWidth, 1)
            let cachedHeight = cachedHeight(for: item)
            let isInitialMeasurement = measuredRows[item.id] == nil
            hostedItem.onHeightMeasured = { [weak self] height in
                guard let self, self.itemByID[item.id] == item,
                      abs(self.parent.contentWidth - contentWidth) <= 0.5 else {
                    return
                }
                let previousHeight = self.measuredRows[item.id]?.height
                self.measuredRows[item.id] = MeasuredRow(
                    item: item, contentWidth: contentWidth,
                    height: height
                )
                if isInitialMeasurement, previousHeight.map({ abs($0 - height) > 0.5 }) ?? true {
                    // Initial Markdown layout can settle after the tail is already
                    // visible. Preserve its position before the new height reaches AppKit.
                    self.scheduleHeightUpdate(for: item.id, preservesInitialBottom: true)
                }
                self.schedulePendingScrollToEnd()
            }
            hostedItem.onHeightChange = { [weak self] in
                self?.scheduleHeightUpdate(for: item.id, preservesInitialBottom: isInitialMeasurement)
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
                    .frame(width: viewportWidth)
                    .fixedSize(horizontal: false, vertical: true)
                ),
                measurementKey: item.id,
                cachedHeight: cachedHeight,
                requiresMeasurement: cachedHeight == nil
            )
        }

        private func trailingContentItem(in items: [ChatTranscriptNativeItem]) -> ChatTranscriptNativeItem? {
            items.last { item in
                if case .entry = item.content { return true }
                return false
            } ?? items.last
        }

        private func scheduleHeightUpdate(for itemID: String, preservesInitialBottom: Bool = false) {
            pendingHeightUpdateIDs.insert(itemID)
            let followsChangingTail = parent.autoFollowChangingTail
                && trailingContentItem(in: parent.items)?.id == itemID
            heightUpdateFollowsBottom = heightUpdateFollowsBottom
                || ((followsChangingTail || preservesInitialBottom) && isNearBottom)
            guard !heightUpdateScheduled else { return }
            heightUpdateScheduled = true
            let viewportAnchor = captureViewportAnchor(followsBottom: false)
            let positionsInitially = pendingScrollToEnd
            let generation = parentUpdateGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let followsBottom = self.heightUpdateFollowsBottom
                self.heightUpdateFollowsBottom = false
                self.heightUpdateScheduled = false
                let changedIDs = self.pendingHeightUpdateIDs
                self.pendingHeightUpdateIDs.removeAll(keepingCapacity: true)
                self.invalidateRows(changedIDs)
                // Let AppKit lay out the changed rows before restoring the viewport.
                // Forcing a subtree layout here can schedule another height update
                // while the current one is still draining the main queue.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parentUpdateGeneration == generation else { return }
                    if positionsInitially {
                        self.schedulePendingScrollToEnd()
                        return
                    }
                    if followsBottom {
                        self.scrollToBottom(animated: false)
                    } else {
                        self.restoreViewport(viewportAnchor)
                        self.updateNearBottom()
                    }
                    self.updateVisibleItem()
                }
            }
        }

        private func invalidateRows(_ itemIDs: some Sequence<String>) {
            guard let layout = collectionView?.collectionViewLayout else { return }
            let indexPaths = Set(itemIDs.compactMap { dataSource?.indexPath(for: $0) })
            guard !indexPaths.isEmpty else { return }
            let context = NSCollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: indexPaths)
            layout.invalidateLayout(with: context)
        }

        private func schedulePendingScrollToEnd() {
            guard pendingScrollToEnd, !scrollToEndScheduled else { return }
            scrollToEndScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollToEndScheduled = false
                guard self.pendingScrollToEnd else { return }
                self.scrollToBottom(animated: false)
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
                    self?.updateNearBottom(preservesLayoutPosition: true)
                    self?.updateVisibleItem()
                    self?.checkHistoryScroll()
                }
            }
            liveScrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A reader's scroll takes precedence over initial positioning.
                    self?.pendingScrollToEnd = false
                    self?.isUserScrolling = true
                    self?.parentUpdateGeneration &+= 1
                }
            }
            liveScrollEndObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification, object: scrollView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isUserScrolling = false }
            }
        }

        private func checkHistoryScroll() {
            guard let scrollView else { return }
            if historyScrollTrigger.didScroll(
                distanceFromTop: scrollView.contentView.bounds.minY + parent.topInset,
                isUserInitiated: isUserScrolling
            ) {
                // Bounds notifications can arrive during a SwiftUI update.
                DispatchQueue.main.async { [weak self] in self?.parent.onReachedTop() }
            }
        }

        func stopObservingScroll() {
            if let liveScrollEndObserver {
                NotificationCenter.default.removeObserver(liveScrollEndObserver)
                self.liveScrollEndObserver = nil
            }
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            if let liveScrollObserver {
                NotificationCenter.default.removeObserver(liveScrollObserver)
                self.liveScrollObserver = nil
            }
        }

        func update(parent: AppKitChatTranscriptCollection, initial: Bool) {
            guard let collectionView, let scrollView else { return }
            let explicitScroll = previousScrollRequest != parent.scrollToEndRequest
            if initial || explicitScroll {
                pendingScrollToEnd = true
            }
            let targetedScroll = previousScrollTarget != parent.scrollTarget
            if targetedScroll, parent.scrollTarget != nil {
                pendingScrollToEnd = false
            }
            let widthChanged = abs(previousContentWidth - parent.contentWidth) > 0.5
            let bottomInsetChanged = abs(previousBottomInset - parent.bottomInset) > 0.5
            let identitiesChanged = previousItems.map(\.id) != parent.items.map(\.id)
            let presentationChanged = previousPresentationRevision != parent.presentationRevision
            let oldByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
            let changedIDs = parent.items.compactMap { item -> String? in
                // Agent colors can arrive after the messages. Refresh their hosting
                // views without treating every streaming delta as a style change.
                guard oldByID[item.id] != item || widthChanged || presentationChanged else { return nil }
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
            let replacedTail = oldEntryIDs.last.map { oldTailID in
                oldEntryIDs.count <= newEntryIDs.count
                    && !newEntryIDs.contains(oldTailID)
                    && oldEntryIDs.dropLast().elementsEqual(newEntryIDs.prefix(oldEntryIDs.count - 1))
            } ?? false
            let followsExistingTail = (parent.autoFollowChangingTail && changedTail && !widthChanged)
                || replacedTail
            if replacedTail && isNearBottom {
                // Completion replaces the streaming row's identity. Keep the tail
                // visible until its new content has been measured.
                pendingScrollToEnd = true
            }
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
            if identitiesChanged {
                measuredRows = measuredRows.filter { itemByID[$0.key] != nil }
            }
            // Changed rows reject their old measurement in cachedHeight, but retain
            // it as an estimate until measured again, including offscreen rows.
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
                dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
                    self?.schedulePendingScrollToEnd()
                }
            } else if !changedIDs.isEmpty {
                // Keep the hosting view and its local state alive during streaming.
                for id in visibleChangedIDs {
                    guard let indexPath = dataSource?.indexPath(for: id),
                          let hostedItem = collectionView.item(at: indexPath) as? AppKitHostedTranscriptItem,
                          let item = itemByID[id] else { continue }
                    configure(hostedItem, with: item)
                }
                if !visibleChangedIDs.isEmpty {
                    invalidateRows(visibleChangedIDs)
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
                    if targetedScroll || (!explicitScroll && !initial && !viewportAnchor.followsBottom) {
                        self.updateNearBottom()
                    }
                    self.updateVisibleItem()
                }
            }

            previousItems = parent.items
            previousPresentationRevision = parent.presentationRevision
            previousContentWidth = parent.contentWidth
            previousTopInset = parent.topInset
            previousBottomInset = parent.bottomInset
            previousScrollRequest = parent.scrollToEndRequest
            previousScrollTarget = parent.scrollTarget
            schedulePendingScrollToEnd()
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
                candidate.id != "reveal-earlier" && candidate.frame.maxY >= bounds.minY - 0.5
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

        private func updateNearBottom(preservesLayoutPosition: Bool = false) {
            guard let collectionView, let scrollView else {
                isNearBottom = true
                return
            }
            let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
            let heightChanged = abs(contentHeight - previousLayoutHeight) > 0.5
            previousLayoutHeight = contentHeight
            // A bounds notification can come from asynchronous row measurement,
            // before we restore the viewport. It is not a reader scrolling away.
            if preservesLayoutPosition && heightChanged && isNearBottom { return }
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
            // Track the requested position while asynchronous measurements settle.
            // A transient estimated content height must not cancel bottom following.
            isNearBottom = true
            // Self-sizing rows preceding the tail can move it after the first
            // scroll. Finish initial positioning once the tail is measured and
            // actually visible, without repeatedly following history updates.
            if measuredRows[parent.items[indexPath.item].id] != nil,
               collectionView.item(at: indexPath) != nil,
               let scrollView {
                let height = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
                if height <= scrollView.contentView.bounds.height
                    || scrollView.contentView.bounds.maxY >= height + parent.bottomInset - 1 {
                    pendingScrollToEnd = false
                }
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
final class AppKitChatTranscriptScrollView: NSScrollView {
    var onLayout: (@MainActor () -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}
#endif
