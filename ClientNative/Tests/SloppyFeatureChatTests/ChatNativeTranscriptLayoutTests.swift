#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("Native transcript layout", .serialized)
@MainActor
struct ChatNativeTranscriptLayoutTests {
    @Test("preferred height follows content growth and shrinkage")
    func preferredHeightFollowsContent() {
        let item = AppKitHostedTranscriptItem()
        item.loadView()
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: 0, section: 0))
        attributes.size = NSSize(width: 480, height: 100)

        for height: CGFloat in [40, 360, 80] {
            item.configure(rootView: AnyView(Color.clear.frame(width: 480, height: height)))
            let fitted = item.preferredLayoutAttributesFitting(attributes)
            #expect(abs(fitted.size.height - height) <= 1)
            #expect(fitted.size.width == 480)
            #expect(attributes.size.height == 100)
        }
    }

    @Test("streaming updates preserve the hosting view")
    func streamingPreservesHostingView() throws {
        let item = AppKitHostedTranscriptItem()
        item.loadView()
        item.configure(rootView: AnyView(Text("First").frame(width: 400)))
        let original = try #require(item.view.subviews.first)
        for count in 1...100 {
            item.configure(rootView: AnyView(Text(String(repeating: "More text ", count: count)).frame(width: 400)))
        }
        #expect(item.view.subviews.count == 1)
        #expect(item.view.subviews.first === original)
    }

    @Test("collection updates keep row identity and lay out growing rows without overlap")
    func collectionStreamingLayout() async throws {
        _ = NSApplication.shared
        func parent(height: Int, revision: UInt) -> AppKitChatTranscriptCollection {
            AppKitChatTranscriptCollection(
                items: [
                    ChatTranscriptNativeItem(id: "first", content: .revealEarlier(count: height)),
                    ChatTranscriptNativeItem(id: "second", content: .revealEarlier(count: 60)),
                ],
                contentWidth: 400, topInset: 0, bottomInset: 0,
                scrollToEndRequest: 0, renderRevision: revision, reduceMotion: true
            ) { item in
                if case .revealEarlier(let height) = item.content {
                    return AnyView(Color.clear.frame(height: CGFloat(height)))
                }
                return AnyView(EmptyView())
            }
        }
        let initial = parent(height: 80, revision: 1)
        let coordinator = initial.makeCoordinator()
        let layout = NSCollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
            let item = NSCollectionLayoutItem(layoutSize: size)
            return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
        }
        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.register(AppKitHostedTranscriptItem.self,
                            forItemWithIdentifier: AppKitHostedTranscriptItem.identifier)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))
        scroll.documentView = collection
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil }
        coordinator.collectionView = collection
        coordinator.scrollView = scroll
        coordinator.installDataSource(on: collection)
        coordinator.update(parent: initial, initial: true)
        for _ in 0..<4 {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let firstPath = IndexPath(item: 0, section: 0)
        let secondPath = IndexPath(item: 1, section: 0)
        let first = try #require(collection.item(at: firstPath))
        coordinator.update(parent: parent(height: 300, revision: 2), initial: false)
        for _ in 0..<4 {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        #expect(collection.item(at: firstPath) === first)
        let firstFrame = try #require(layout.layoutAttributesForItem(at: firstPath)).frame
        let secondFrame = try #require(layout.layoutAttributesForItem(at: secondPath)).frame
        #expect(firstFrame.height >= 300)
        #expect(secondFrame.minY >= firstFrame.maxY - 0.5)
    }

    @Test("streamed markdown and code blocks grow without retaining the previous height")
    func markdownGrowth() async {
        let item = AppKitHostedTranscriptItem()
        item.loadView()
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: 0, section: 0))
        attributes.size = NSSize(width: 400, height: 100)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = item.view
        defer { window.contentView = nil }
        var heights: [CGFloat] = []
        for count in [1, 20, 40] {
            let text = "## Response\n\n" + String(repeating: "A paragraph of **streaming** text.\n\n", count: count)
                + "```swift\nlet answer = 42\n```"
            let message = ChatMessage(id: "streaming-assistant-test", role: .assistant,
                                      segments: [ChatMessageSegment(kind: .text, text: text)])
            item.configure(rootView: AnyView(ChatBubbleView(message: message)
                .frame(width: 400).fixedSize(horizontal: false, vertical: true)))
            // Textual publishes parsed markdown asynchronously after the view mounts.
            for _ in 0..<30 {
                item.view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
            heights.append(item.preferredLayoutAttributesFitting(attributes).size.height)
        }
        #expect(heights[1] > heights[0])
        #expect(heights[2] > heights[1])
    }

    @Test("history with a message taller than the viewport can scroll in both directions")
    func oversizedMessageScrolls() async throws {
        _ = NSApplication.shared
        let transcript = AppKitChatTranscriptCollection(
            items: [
                ChatTranscriptNativeItem(id: "first", content: .revealEarlier(count: 100)),
                ChatTranscriptNativeItem(id: "long", content: .revealEarlier(count: 1800)),
                ChatTranscriptNativeItem(id: "last", content: .revealEarlier(count: 100)),
            ],
            contentWidth: 400, topInset: 24, bottomInset: 120,
            scrollToEndRequest: 0, renderRevision: 1, reduceMotion: true
        ) { item in
            guard case .revealEarlier(let height) = item.content else { return AnyView(EmptyView()) }
            return AnyView(Text("Message").frame(height: CGFloat(height)))
        }
        let host = NSHostingView(rootView: transcript)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<10 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try #require(scrollView(in: host))
        let document = try #require(scroll.documentView as? NSCollectionView)
        #expect(scroll.bounds.height <= 400)
        #expect(document.frame.height >= 2000)
        #expect(scroll.contentView.bounds.maxY - scroll.contentInsets.bottom >= document.frame.height - 1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.minY >= 590)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(abs(scroll.contentView.bounds.minY) <= 1)

        host.frame.size.width = 620
        for _ in 0..<6 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
        #expect(abs(document.frame.width - scroll.contentSize.width) <= 1)
        #expect(document.frame.height >= 2000)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.minY >= 590)
    }

    @Test("wrapped text reports its full height")
    func wrappedTextHeight() {
        let item = AppKitHostedTranscriptItem()
        item.loadView()
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: 0, section: 0))
        attributes.size = NSSize(width: 300, height: 100)
        item.configure(rootView: AnyView(Text("Short").frame(width: 300).fixedSize(horizontal: false, vertical: true)))
        let shortHeight = item.preferredLayoutAttributesFitting(attributes).size.height
        item.configure(rootView: AnyView(Text(String(repeating: "A line of streamed text.\n", count: 40))
            .frame(width: 300).fixedSize(horizontal: false, vertical: true)))
        let longHeight = item.preferredLayoutAttributesFitting(attributes).size.height
        #expect(longHeight > shortHeight * 20)
    }
}
#endif
