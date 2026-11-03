#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyUITestSupport
import SloppyClientCore
import SloppyClientUI
@testable import SloppyFeatureChat

@Suite("Activity expansion layout", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatActivityExpansionLayoutTests {
    @Test("scrolling expanded tool output preserves activity geometry and expansion")
    func scrollingLongToolOutput() async throws {
        let output = (0..<160).map { "Line \($0): " + String(repeating: "command output ", count: 8) }.joined(separator: "\n")
        var segments: [ChatMessageSegment] = [
            .init(kind: .toolResult, text: output, title: "runtime.exec")
        ]
        for index in 1..<18 {
            segments.append(.init(kind: .toolCall, text: "Read file \(index)", title: "files.read.\(index)", status: "running"))
        }
        let fixture = ActivityFixture(segments: segments)
        defer { fixture.close() }
        await fixture.settle()
        let expand = try #require(fixture.button(label: "Expand activity"))
        #expect((expand as AnyObject).accessibilityPerformPress?() == true)
        await fixture.settle()
        let outputHeader = try #require(fixture.button(label: "runtime.exec"))
        #expect((outputHeader as AnyObject).accessibilityPerformPress?() == true)
        await fixture.settle()

        let row = try fixture.row(0)
        let following = try fixture.row(1)
        let rowFrame = row.view.frame
        let followingFrame = following.view.frame
        let innerScroll = try #require(fixture.nestedScroll(in: row.view))
        let document = try #require(innerScroll.documentView)
        let documentHeight = document.frame.height
        #expect(documentHeight > innerScroll.contentSize.height * 3)

        // Repeatedly cross the lazy stack's realization boundaries in both directions.
        // The enclosing transcript row must stay fixed while the reader scrolls output.
        for step in (0..<24).map({ CGFloat($0) / 23 }) + (0..<24).reversed().map({ CGFloat($0) / 23 }) {
            let y = max(0, documentHeight - innerScroll.contentSize.height) * step
            innerScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            innerScroll.reflectScrolledClipView(innerScroll.contentView)
            fixture.window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            #expect(abs(document.frame.height - documentHeight) <= 1)
            #expect(abs(row.view.frame.height - rowFrame.height) <= 1)
            #expect(abs(following.view.frame.minY - followingFrame.minY) <= 1)
        }
        #expect(innerScroll.contentView.bounds.minY <= 1)
        #expect(document.frame.height >= documentHeight - 1)
        try fixture.capture(name: "scrolled-output")
    }

    @Test("expanding running tools repositions the following visible row")
    func runningToolsDoNotOverlapFollowingStatus() async throws {
        let fixture = ActivityFixture()
        defer { fixture.close() }
        await fixture.settle()
        let tools = try fixture.row(0)
        let following = try fixture.row(1)
        let originalHost = try #require(tools.view.subviews.first)

        for _ in 0..<3 {
            let expand = try #require(fixture.button(label: "Expand activity"))
            #expect((expand as AnyObject).accessibilityPerformPress?() == true)
            await fixture.settle()
            let controller = try #require(tools.children.first as? NSHostingController<AnyView>)
            let expandedHeight = controller.sizeThatFits(in: NSSize(width: 500, height: 10_000)).height
            #expect(expandedHeight > 260)
            // Inspect the actual displayed item frames, not only the layout's attributes.
            #expect(following.view.frame.minY >= tools.view.frame.minY + expandedHeight - 1)
            #expect(tools.view.subviews.first === originalHost)
            try fixture.capture(name: "expanded")

            let collapse = try #require(fixture.button(label: "Collapse activity"))
            #expect((collapse as AnyObject).accessibilityPerformPress?() == true)
            await fixture.settle()
            #expect(tools.view.frame.height < expandedHeight - 100)
            #expect(following.view.frame.minY >= tools.view.frame.maxY - 1)
            #expect(following.view.frame.minY <= tools.view.frame.maxY + 1)
        }
        try fixture.capture(name: "collapsed")
    }
}

@MainActor
private final class ActivityFixture {
    let collection = NSCollectionView()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 550))
    let window: NSWindow
    let coordinator: AppKitChatTranscriptCollection.Coordinator

    init(segments customSegments: [ChatMessageSegment]? = nil) {
        _ = NSApplication.shared
        AppKitTestAccessibility.enable()
        var segments: [ChatMessageSegment] = []
        for index in 0..<5 {
            segments.append(.init(kind: .toolCall, text: "Read project files", title: "files.list", status: "running"))
            if index < 4 {
                segments.append(.init(kind: .toolResult, text: "Sources, Tests", title: "files.list"))
            }
        }
        let message = ChatMessage(id: "tools", role: .system, segments: customSegments ?? segments)
        let parent = AppKitChatTranscriptCollection(
            items: [
                .init(id: "tools", content: .entry(.systemGroup([message]), bottomSpacing: 0,
                                                  activeMessageIDs: [message.id], providerRecoveryMessageIDs: [])),
                .init(id: "status", content: .thinking(label: "Responding", details: nil))
            ],
            contentWidth: 440, topInset: 0, bottomInset: 0,
            scrollToEndRequest: 0, autoFollowChangingTail: false, renderRevision: 1, reduceMotion: true
        ) { item in
            let content: AnyView
            if item.id == "tools" {
                content = AnyView(ChatSystemMessageGroupView(messages: [message], activeRunMessageIDs: [message.id]))
            } else {
                content = AnyView(Text("Responding").font(.headline).frame(maxWidth: .infinity, alignment: .leading).frame(height: 48))
            }
            return AnyView(content.environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        }
        coordinator = parent.makeCoordinator()
        window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        collection.collectionViewLayout = AppKitChatTranscriptLayout()
        collection.register(AppKitHostedTranscriptItem.self, forItemWithIdentifier: AppKitHostedTranscriptItem.identifier)
        scroll.documentView = collection
        scroll.drawsBackground = false
        window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        window.contentView = scroll
        coordinator.collectionView = collection
        coordinator.scrollView = scroll
        coordinator.installDataSource(on: collection)
        coordinator.update(parent: parent, initial: true)
        window.orderFront(nil)
    }

    func row(_ index: Int) throws -> NSCollectionViewItem {
        try #require(collection.item(at: IndexPath(item: index, section: 0)))
    }

    func nestedScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.nestedScroll(in: $0) }.first
    }

    func button(label: String) -> NSObject? {
        func attribute(_ name: String, of object: NSObject) -> Any? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func find(_ elements: [Any]) -> NSObject? {
            for case let element as NSObject in elements {
                if attribute("accessibilityLabel", of: element) as? String == label { return element }
                if let match = find(attribute("accessibilityChildren", of: element) as? [Any] ?? []) { return match }
            }
            return nil
        }
        return find(collection.accessibilityChildren() ?? [])
    }

    func settle() async {
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func capture(name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_ACTIVITY_LAYOUT_PROOF_DIR"] else { return }
        let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("activity-\(name).png"))
    }

    func close() {
        coordinator.stopObservingScroll()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}
#endif
