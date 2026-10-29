#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
import Testing
@testable import SloppyFeatureChat
@testable import Textual

@Suite("Chat annotation interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatAnnotationInteractionTests {
    @Test("sent annotation chips open their preserved selections and comments", arguments: [ColorScheme.light, .dark])
    func sentAnnotationBubble(scheme: ColorScheme) async throws {
        AppKitTestAccessibility.enable()
        let content = ChatComposerQuote.messageContent("Please update these sections.", quotes: [
            .init(text: "The host migration is not finished yet.", comment: "Check the linked pull request before changing this."),
            .init(text: "Keep the versioned mode enabled by default.", comment: "Add this to acceptance criteria."),
        ])
        let message = ChatMessage(role: .user, segments: [.init(kind: .text, text: content)])
        let host = NSHostingView(rootView: ChatBubbleView(message: message)
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(scheme == .dark ? AppTheme.sloppyDark.colors.background : AppTheme.sloppyLight.colors.background)
            .environment(\.theme, scheme == .dark ? .sloppyDark : .sloppyLight)
            .environment(\.userInterfaceIdiom, .desktop).preferredColorScheme(scheme))
        let window = makeWindow(host: host, size: CGSize(width: 720, height: 460))
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        let chip = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.user-message.annotations"))
        let frame = try #require(AppKitTestAccessibility.frame(of: chip))
        #expect(frame.height < 40)
        #expect(frame.width < 200)
        let body = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.user-message.body"))
        let bodyFrame = try #require(AppKitTestAccessibility.frame(of: body))
        #expect(bodyFrame.height < 80)
        try capture(host, name: "sent-annotations-\(scheme)-closed")
        #expect(AppKitTestAccessibility.press(chip))
        try await Task.sleep(for: .milliseconds(350))
        let popover = try #require(NSApp.windows.compactMap(\.contentView).first {
            AppKitTestAccessibility.element(in: $0, identifier: "chat.user-message.annotation.0.selection") != nil
        })
        #expect(AppKitTestAccessibility.element(in: popover, identifier: "chat.user-message.annotation.0.comment") != nil)
        #expect(AppKitTestAccessibility.element(in: popover, identifier: "chat.user-message.annotation.1.selection") != nil)
        #expect(AppKitTestAccessibility.element(in: popover, identifier: "chat.user-message.annotation.1.comment") != nil)
        try capture(popover, name: "sent-annotations-\(scheme)-open")
        #expect(AppKitTestAccessibility.press(chip))
        try await Task.sleep(for: .milliseconds(300))
        #expect(!NSApp.windows.filter(\.isVisible).compactMap(\.contentView).contains {
            AppKitTestAccessibility.element(in: $0, identifier: "chat.user-message.annotation.0.selection") != nil
        })
    }

    @Test("text annotations stay at their source and can be reopened, edited, and emptied")
    func anchoredTextAnnotationEditing() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: AnnotationInteractionNotifications(),
            onOpenSettings: { _ in })
        model.transcript.replaceAll([AnnotationTextFixture.message])
        let recorder = SelectionToolbarRecorder()
        let host = NSHostingView(rootView: AnnotationTextFixture(model: model, recorder: recorder)
            .environment(\.theme, .sloppyDark).environment(\.userInterfaceIdiom, .desktop)
            .preferredColorScheme(.dark))
        let window = makeWindow(host: host, size: CGSize(width: 900, height: 650))
        defer { model.quoteAnnotationPresenter.close(); window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        model.composerDraft.text = "General request"
        let overlay = try #require(descendants(host).compactMap { $0 as? NSTextInteractionView }.first {
            $0.model.text(in: TextRange(start: $0.model.startPosition, end: $0.model.endPosition)).contains("python3")
        })
        let rendered = overlay.model.text(in: TextRange(start: overlay.model.startPosition, end: overlay.model.endPosition))
        let range = (rendered as NSString).range(of: "python3 -m http.server 8765")
        let start = try #require(overlay.model.position(from: overlay.model.startPosition, offset: range.location))
        let end = try #require(overlay.model.position(from: start, offset: range.length))
        #expect(window.makeFirstResponder(overlay))
        let selectedRect = overlay.model.firstRect(for: TextRange(start: start, end: end))
        for (type, x) in [(NSEvent.EventType.leftMouseDown, selectedRect.minX + 0.1),
                          (.leftMouseDragged, selectedRect.maxX - 0.1), (.leftMouseUp, selectedRect.maxX - 0.1)] {
            let point = overlay.convert(NSPoint(x: x, y: selectedRect.midY), to: nil)
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: overlay.mouseDown(with: event)
            case .leftMouseDragged: overlay.mouseDragged(with: event)
            default: overlay.mouseUp(with: event)
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let toolbar = try #require(overlay.selectionToolbar.panel)
        let toolbarView = try #require(toolbar.contentView)
        #expect(toolbar.frame.height <= 36)
        #expect(toolbar.frame.width < 340)
        #expect(window.firstResponder === overlay)
        let sideChat = try #require(AppKitTestAccessibility.element(in: toolbarView, identifier: "textual.selection.action.1"))
        try capture(toolbarView, name: "selection-toolbar")
        #expect(AppKitTestAccessibility.press(sideChat))
        #expect(recorder.selection == "python3 -m http.server 8765")
        #expect(overlay.selectionToolbar.panel == nil)
        overlay.showSelectionToolbar()
        try await Task.sleep(for: .milliseconds(100))
        let addView = try #require(overlay.selectionToolbar.panel?.contentView)
        let add = try #require(AppKitTestAccessibility.element(in: addView, identifier: "textual.selection.action.0"))
        #expect(AppKitTestAccessibility.press(add))
        try await Task.sleep(for: .milliseconds(300))
        let quote = try #require(model.composerQuotes.first)
        #expect(quote.source?.messageID == "annotation-source")
        #expect(quote.source?.location.range == range)
        #expect(quote.source?.location.scope != "root")
        let popover = try #require(model.quoteAnnotationPresenter.popover)
        let popoverView = try #require(popover.contentViewController?.view)
        let editor = try #require(popoverView.window?.firstResponder as? NSTextView)
        editor.insertText("Fix this command", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.composerQuotes.first?.comment == "Fix this command")
        #expect(model.composerDraft.text == "General request")
        try capture(host, name: "anchored-text-attachment")
        try capture(popoverView, name: "anchored-text-editor")
        model.quoteAnnotationPresenter.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.composerQuotes.count == 1)
        let chip = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.composer.annotation.\(quote.id).edit"))
        #expect(AppKitTestAccessibility.press(chip))
        try await Task.sleep(for: .milliseconds(150))
        let reopened = try #require(model.quoteAnnotationPresenter.popover?.contentViewController?.view.window?.firstResponder as? NSTextView)
        #expect(reopened.string == "Fix this command")
        reopened.insertText("Updated comment", replacementRange: NSRange(location: 0, length: (reopened.string as NSString).length))
        try await Task.sleep(for: .milliseconds(100))
        model.quoteAnnotationPresenter.close()
        #expect(model.composerQuotes.first?.comment == "Updated comment")
        // Click the marked source text itself, after the native selection has gone away.
        overlay.model.selectedRange = nil
        let location = try #require(quote.source?.location)
        let selection = try #require(overlay.annotationRange(for: location))
        let rect = try #require(overlay.model.selectionRects(for: selection).first?.rect)
        let point = overlay.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { overlay.mouseDown(with: event) }
            else { overlay.mouseUp(with: event) }
        }
        try await Task.sleep(for: .milliseconds(150))
        let sourceEditor = try #require(model.quoteAnnotationPresenter.popover?.contentViewController?.view.window?.firstResponder as? NSTextView)
        #expect(sourceEditor.string == "Updated comment")
        sourceEditor.insertText("", replacementRange: NSRange(location: 0, length: (sourceEditor.string as NSString).length))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.composerQuotes.count == 1)
        model.quoteAnnotationPresenter.close()
        #expect(model.composerQuotes.isEmpty)
        #expect(model.pendingComposerQuotes.isEmpty)
        overlay.model.selectedRange = TextRange(start: start, end: end)
        overlay.showSelectionToolbar()
        #expect(overlay.selectionToolbar.panel != nil)
        window.setContentSize(NSSize(width: 700, height: 650))
        try await Task.sleep(for: .milliseconds(100))
        #expect(overlay.selectionToolbar.panel == nil)
        #expect(overlay.model.selectedRange != nil)
        let contextEvent = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(overlay.menu(for: contextEvent))
        #expect(menu.items.contains { $0.title == "More details" })
        #expect(menu.items.contains { $0.action == NSSelectorFromString("copy:") })
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @Test("image points and dragged areas focus and save their own comments", arguments: [ColorScheme.light, .dark])
    func imagePointAndAreaComments(scheme: ColorScheme) async throws {
        let image = NSImage(size: NSSize(width: 800, height: 400))
        image.lockFocus()
        NSColor.gray.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 800, height: 400)).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var data = try #require(bitmap.representation(using: .png, properties: [:]))
        if let source = ProcessInfo.processInfo.environment["SLOPPY_ANNOTATION_SOURCE_IMAGE"] {
            data = try Data(contentsOf: URL(fileURLWithPath: source))
        }
        let attachment = ChatComposerAttachment(name: "screenshot.png", mimeType: "image/png", data: data)
        AppKitTestAccessibility.enable()
        var saved: [ChatImageAnnotation] = []
        let host = NSHostingView(rootView: ChatImageAnnotationEditor(attachment: attachment, save: { saved = $0 })
            .environment(\.theme, scheme == .dark ? .sloppyDark : .sloppyLight)
            .preferredColorScheme(scheme))
        let window = makeWindow(host: host, size: CGSize(width: 1000, height: 820))
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        try capture(host, name: "image-before-click")
        let zoomIn = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.zoom-in"))
        #expect(AppKitTestAccessibility.press(zoomIn))
        #expect(AppKitTestAccessibility.press(zoomIn))
        try await Task.sleep(for: .milliseconds(100))
        try capture(host, name: scheme == .dark ? "image-zoom-dark" : "image-zoom-light")
        let canvas = try #require(descendants(host).compactMap { $0 as? ChatImageAnnotationPointerInput.AnnotationPointerView }.first)
        // Pan uses the real pointer path and must not create a note.
        canvas.isPanning = true
        let panStart = canvas.convert(CGPoint(x: 300, y: 200), to: nil)
        let panEnd = canvas.convert(CGPoint(x: 340, y: 220), to: nil)
        for (type, location) in [(NSEvent.EventType.leftMouseDown, panStart), (.leftMouseDragged, panEnd), (.leftMouseUp, panEnd)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        canvas.isPanning = false
        try await Task.sleep(for: .milliseconds(100))
        let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.height * 0.4), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
            try await Task.sleep(for: .milliseconds(50))
        }
        for _ in 0..<100 where !(window.firstResponder is NSTextView) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try capture(host, name: "image-after-click")
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("Pay attention to this section", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.string == "Pay attention to this section")
        let dragStart = host.convert(NSPoint(x: host.bounds.width * 0.4, y: host.bounds.height * 0.3), to: nil)
        let dragEnd = host.convert(NSPoint(x: host.bounds.width * 0.6, y: host.bounds.height * 0.4), to: nil)
        for (type, location) in [(NSEvent.EventType.leftMouseDown, dragStart), (.leftMouseDragged, dragEnd), (.leftMouseUp, dragEnd)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(150))
        try capture(host, name: "image-after-drag")
        let areaEditor = try #require(window.firstResponder as? NSTextView)
        areaEditor.insertText("Widen this area", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        try capture(host, name: scheme == .dark ? "image-dark" : "image-light")
        let fit = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.fit"))
        #expect(AppKitTestAccessibility.press(fit))
        try await Task.sleep(for: .milliseconds(100))
        try capture(host, name: scheme == .dark ? "image-fit-dark" : "image-fit-light")
        let save = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.save"))
        #expect(AppKitTestAccessibility.press(save))
        #expect(saved.count == 2)
        #expect(saved.map(\.comment) == ["Pay attention to this section", "Widen this area"])
        #expect(saved.last?.region.width ?? 0 > 0)
        #expect(saved.last?.region.height ?? 0 > 0)
    }

    @Test("viewer drawing survives zoom, undo, redo and saving to the composer")
    func viewerDrawing() async throws {
        AppKitTestAccessibility.enable()
        let context = try #require(CGContext(data: nil, width: 800, height: 450, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.88, green: 0.87, blue: 0.83, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 450))
        let image = try #require(context.makeImage())
        let original = try ChatImageExport.png(image: image, strokes: [])
        let attachment = ChatComposerAttachment(name: "design.png", mimeType: "image/png", data: original)
        var saved: ChatComposerAttachment?
        let host = NSHostingView(rootView: ChatImageAnnotationEditor(attachment: attachment, onSave: { saved = $0 })
            .environment(\.theme, .sloppyDark))
        let window = makeWindow(host: host, size: CGSize(width: 1100, height: 760))
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        try capture(host, name: "viewer-fit")
        let pen = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.tool.pen"))
        #expect(AppKitTestAccessibility.press(pen))
        try await Task.sleep(for: .milliseconds(100))
        let canvas = try #require(descendants(host).compactMap { $0 as? ChatImageAnnotationPointerInput.AnnotationPointerView }.first)
        let start = canvas.convert(CGPoint(x: 260, y: 260), to: nil)
        let end = canvas.convert(CGPoint(x: 620, y: 330), to: nil)
        for (type, location) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 4, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let undo = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.markup.undo"))
        #expect(AppKitTestAccessibility.press(undo))
        try await Task.sleep(for: .milliseconds(100))
        let redo = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.markup.redo"))
        #expect(AppKitTestAccessibility.press(redo))
        let zoom = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.zoom-in"))
        #expect(AppKitTestAccessibility.press(zoom))
        try await Task.sleep(for: .milliseconds(100))
        try capture(host, name: "viewer-drawing-zoom")
        let fit = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.fit"))
        #expect(AppKitTestAccessibility.press(fit))
        try await Task.sleep(for: .milliseconds(100))
        try capture(host, name: "viewer-drawing-fit")
        let save = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.image.annotations.save"))
        #expect(AppKitTestAccessibility.press(save))
        let result = try #require(saved)
        #expect(result.data == original)
        #expect(result.markup?.strokes.count == 1)
        #expect(result.markup?.pngData != original)
        #expect(result.upload.contentBase64 == result.markup?.pngData.base64EncodedString())
    }

    private func makeWindow<V: View>(host: NSHostingView<V>, size: CGSize) -> NSWindow {
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func capture(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_ANNOTATION_SCREENSHOTS"] else { return }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
@MainActor
private final class AnnotationInteractionNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif

#if os(macOS)
@MainActor
private struct AnnotationTextFixture: View {
    let model: ChatScreenViewModel
    let recorder: SelectionToolbarRecorder
    static let message = ChatMessage(id: "annotation-source", role: .assistant, segments: [
        .init(kind: .text, text: """
        Run the command below, then inspect the page.

        ```sh
        npm test
        python3 -m http.server 8765
        ```

        The selected command should keep its annotation here.
        """)
    ])
    var body: some View {
        VStack {
            ChatTranscriptPane(viewModel: model, transcript: model.transcript, isLoadingTranscript: false,
                scrollToEndRequest: 0, contentWidth: 840, messagesTopInset: 30, composerScrollInset: 20,
                showsThinkingIndicator: false, isRunActive: false, runStatusLabel: "", runStatusDetails: nil,
                workingTreeSourceControl: nil, inputRequest: nil, isSubmittingInputResponse: false,
                inputRequestErrorMessage: nil, providerSettingsRecoveryMessageIDs: [],
                onSubmitInputResponse: { _ in }, onCancelInputRequest: {}, onForkFromMessage: { _ in },
                onOpenProviderSettings: {})
            ChatComposerView(draft: model.composerDraft, tabs: [], viewModel: model).padding()
        }
        .environment(\.chatTextSelectionActions, ChatTextSelectionActions(
            addToChat: model.addQuoteToComposer,
            moreDetails: model.askForMoreDetails,
            askInSideChat: { recorder.selection = $0 },
            addAnnotation: model.addAnchoredQuoteToComposer,
            annotations: model.composerQuotes,
            editAnnotation: model.editAnchoredComposerQuote,
            resolveAnnotation: { id, context in model.quoteAnnotationPresenter.anchors[id] = context }))
    }
}

@MainActor
private final class SelectionToolbarRecorder {
    var selection: String?
}
#endif
