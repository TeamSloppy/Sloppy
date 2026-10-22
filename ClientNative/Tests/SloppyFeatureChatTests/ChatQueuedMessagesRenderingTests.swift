#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureChat

@Suite("Queued message appearance", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatQueuedMessagesRenderingTests {
    @Test("queue uses the active semantic surface even with a mismatched system scheme")
    func semanticSurfaceAndCompactLayout() async throws {
        for (name, theme, scheme) in [("dark", AppTheme.sloppyDark, ColorScheme.dark),
                                       ("light", .sloppyLight, .light),
                                       ("active-light-dark-scheme", .sloppyLight, .dark)] {
            let message = ChatQueuedMessage(content: "", attachments: [attachment, attachment])
            let (host, window) = makeWindow(messages: [message], theme: theme, scheme: scheme, width: 620)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(180))
            let bitmap = try bitmap(host)
            let actual = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            let swatch = NSHostingView(rootView: theme.colors.surfaceRaised.frame(width: 620, height: 80).preferredColorScheme(scheme))
            swatch.frame = NSRect(x: 0, y: 0, width: 620, height: 80)
            let swatchWindow = NSWindow(contentRect: swatch.frame, styleMask: [.titled], backing: .buffered, defer: false)
            swatchWindow.isReleasedWhenClosed = false
            swatchWindow.contentView = swatch
            swatchWindow.orderFront(nil)
            defer { swatchWindow.close() }
            let expected = try #require(try self.bitmap(swatch).colorAt(x: 300, y: 50)?.usingColorSpace(.deviceRGB))
            #expect(abs(actual.redComponent - expected.redComponent) < 0.03)
            #expect(abs(actual.greenComponent - expected.greenComponent) < 0.03)
            #expect(abs(actual.blueComponent - expected.blueComponent) < 0.03)
            #expect(host.fittingSize.height <= 100)
            try capture(bitmap, name: "queue-\(name)")
        }
    }

    @Test("narrow multiple and long previews keep cancellation reachable and ordered")
    func narrowQueueCancellation() async throws {
        AppKitTestAccessibility.enable()
        var queue = ChatMessageQueue()
        let first = queue.enqueue(content: String(repeating: "Long queued preview without sending. ", count: 20), attachments: [])
        let second = queue.enqueue(content: "", attachments: [attachment, attachment])
        queue.enqueue(content: "Third message", attachments: [])
        queue.enqueue(content: "Fourth message", attachments: [])
        let (host, window) = makeWindow(messages: queue.messages, theme: .sloppyDark, scheme: .dark,
                                       width: 300, cancel: { queue.cancel(id: $0) })
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        for message in [first, second] {
            let button = try #require(AppKitTestAccessibility.element(in: host,
                identifier: "chat.message-queue.remove.\(message.id)"))
            let frame = try #require(AppKitTestAccessibility.frame(of: button))
            #expect(frame.width >= 44 && frame.height >= 44)
            #expect(frame.minX >= window.frame.minX && frame.maxX <= window.frame.maxX)
        }
        #expect(host.fittingSize.height < 220)
        try capture(try bitmap(host), name: "queue-narrow-multiple-long")
        let remove = try #require(AppKitTestAccessibility.element(in: host,
            identifier: "chat.message-queue.remove.\(first.id)"))
        #expect(AppKitTestAccessibility.press(remove))
        #expect(queue.messages.first?.id == second.id)
        #expect(queue.messages.count == 3)
    }

    @Test("empty queue occupies no composer space")
    func emptyQueue() async throws {
        let host = NSHostingView(rootView: ChatQueuedMessagesCard(messages: [], cancel: { _ in }))
        #expect(host.fittingSize.height == 0)
    }

    private var attachment: ChatComposerAttachment {
        .init(name: "fixture.txt", mimeType: "text/plain", data: Data("safe local fixture".utf8))
    }

    private func makeWindow(messages: [ChatQueuedMessage], theme: AppTheme, scheme: ColorScheme,
                            width: CGFloat, cancel: @escaping @MainActor (UUID) -> Void = { _ in })
        -> (NSHostingView<AnyView>, NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(ChatQueuedMessagesCard(messages: messages, cancel: cancel)
            .environment(\.theme, theme).preferredColorScheme(scheme).frame(width: width)))
        let window = NSWindow(contentRect: .init(x: 120, y: 160, width: width, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(.init(width: width, height: host.fittingSize.height))
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func capture(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_QUEUE_SCREENSHOTS"] else { return }
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
#endif
