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
    let renderRevision: UInt
    let reduceMotion: Bool
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

    var body: some View {
        #if os(macOS)
        AppKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            renderRevision: renderRevision,
            reduceMotion: reduceMotion,
            renderer: renderer
        )
        #else
        UIKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            renderRevision: renderRevision,
            reduceMotion: reduceMotion,
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
    let renderRevision: UInt
    let reduceMotion: Bool
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

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
        private var previousRenderRevision: UInt?
        private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, String>?

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
                } else if explicitScroll || (wasNearBottom && (contentChanged || bottomInsetChanged)) || initial {
                    self.scrollToBottom(
                        collectionView,
                        animated: explicitScroll && !initial && !parent.reduceMotion
                    )
                }
            }

            previousItems = parent.items
            previousContentWidth = parent.contentWidth
            previousTopInset = parent.topInset
            previousBottomInset = parent.bottomInset
            previousScrollRequest = parent.scrollToEndRequest
            previousRenderRevision = parent.renderRevision
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
    let renderRevision: UInt
    let reduceMotion: Bool
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

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
        scrollView.hasVerticalScroller = true
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
        private var previousRenderRevision: UInt?
        private var scrollObserver: NSObjectProtocol?
        private var isNearBottom = true
        private var heightUpdateScheduled = false

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
                self?.scheduleHeightUpdate()
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
                )
            )
        }

        private func scheduleHeightUpdate() {
            guard !heightUpdateScheduled else { return }
            heightUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.heightUpdateScheduled = false
                let shouldFollow = self.isNearBottom
                self.collectionView?.collectionViewLayout?.invalidateLayout()
                self.collectionView?.layoutSubtreeIfNeeded()
                if shouldFollow {
                    self.scrollToBottom(animated: false)
                }
                self.updateNearBottom()
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
            let wasNearBottom = isNearBottom
            let oldContentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
            let oldOrigin = scrollView.contentView.bounds.origin
            let oldTopInset = previousTopInset
            let didPrepend = didPrependItems(from: previousItems, to: parent.items)
            let explicitScroll = previousScrollRequest != parent.scrollToEndRequest
            let contentChanged = previousRenderRevision != parent.renderRevision
            let widthChanged = abs(previousContentWidth - parent.contentWidth) > 0.5
            let bottomInsetChanged = abs(previousBottomInset - parent.bottomInset) > 0.5

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

            let identitiesChanged = previousItems.map(\.id) != parent.items.map(\.id)
            let oldByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
            let changedIDs = parent.items.compactMap { item -> String? in
                guard oldByID[item.id] != item || widthChanged else { return nil }
                return item.id
            }
            if initial || identitiesChanged {
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(parent.items.map(\.id), toSection: 0)
                snapshot.reloadItems(changedIDs.filter { oldByID[$0] != nil })
                dataSource?.apply(snapshot, animatingDifferences: false)
            } else if !changedIDs.isEmpty {
                // Keep the hosting view and its local state alive during streaming.
                for id in changedIDs {
                    guard let indexPath = dataSource?.indexPath(for: id),
                          let hostedItem = collectionView.item(at: indexPath) as? AppKitHostedTranscriptItem,
                          let item = itemByID[id] else { continue }
                    configure(hostedItem, with: item)
                }
                collectionView.collectionViewLayout?.invalidateLayout()
            }

            DispatchQueue.main.async { [weak self, weak collectionView, weak scrollView] in
                guard let self, let collectionView, let scrollView else { return }
                collectionView.layoutSubtreeIfNeeded()
                if didPrepend && !wasNearBottom {
                    let newHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
                    let topInsetDelta = parent.topInset - oldTopInset
                    scrollView.contentView.scroll(
                        to: NSPoint(
                            x: oldOrigin.x,
                            y: oldOrigin.y + newHeight - oldContentHeight + topInsetDelta
                        )
                    )
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                } else if explicitScroll || (wasNearBottom && (contentChanged || bottomInsetChanged)) || initial {
                    self.scrollToBottom(animated: explicitScroll && !parent.reduceMotion)
                }
                self.updateNearBottom()
            }

            previousItems = parent.items
            previousContentWidth = parent.contentWidth
            previousTopInset = parent.topInset
            previousBottomInset = parent.bottomInset
            previousScrollRequest = parent.scrollToEndRequest
            previousRenderRevision = parent.renderRevision
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

        private func updateNearBottom() {
            guard let collectionView, let scrollView else {
                isNearBottom = true
                return
            }
            let contentHeight = collectionView.collectionViewLayout?.collectionViewContentSize.height ?? 0
            let visibleBottom = scrollView.contentView.bounds.maxY
            isNearBottom = contentHeight <= scrollView.contentView.bounds.height
                || visibleBottom >= contentHeight - 44
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
    private var measuredHeight: CGFloat = 0
    private var measurementGeneration: UInt = 0
    var onHeightChange: (@MainActor () -> Void)?

    override func loadView() {
        view = NSView()
    }

    func configure(rootView: AnyView) {
        measurementGeneration &+= 1
        let generation = measurementGeneration
        let measuredRoot = AnyView(rootView.onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
        } action: { [weak self] height in
            guard let self, height.isFinite, height > 0,
                  abs(self.measuredHeight - height) > 0.5 else { return }
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
        if let hostingView {
            hostingView.rootView = measuredRoot
            return
        }
        let hostingView = NSHostingView(rootView: measuredRoot)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.hostingView = hostingView
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? NSCollectionViewLayoutAttributes,
              let hostingView else { return layoutAttributes }
        hostingView.layoutSubtreeIfNeeded()
        let height = ceil(hostingView.fittingSize.height)
        if height.isFinite && height > 0 {
            attributes.size.height = height
        }
        return attributes
    }
}
#endif
