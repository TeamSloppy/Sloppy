#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureChat

@Suite("Composer reference inserts", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ComposerReferenceRenderingTests {
    private let file = ChatComposerReference(rawText: "@Sources/Package.swift", title: "Package.swift",
        target: .file(projectId: "project", path: "Sources/Package.swift"))
    private let command = ChatComposerReference(rawText: "/abort", title: "/abort", detail: "Abort current processing",
        target: .command(agentId: "agent", name: "abort"))
    private let skill = ChatComposerReference(rawText: "@review-code", title: "Code review",
        target: .skill(agentId: "agent", skillId: "review"))
    private var style: AppKitComposerTextStyle {
        .init(font: .systemFont(ofSize: 14), primaryColor: .labelColor, placeholderColor: .secondaryLabelColor,
              commandColor: .linkColor, mentionColor: .linkColor, tagColor: .linkColor, codeBackgroundColor: .clear)
    }

    @Test func projectionPreservesUnicodeAddressesAndCode() throws {
        _ = NSApplication.shared
        let session = ChatSessionReference(agentId: "agent/a", sessionId: "id-42")
            .markdown(title: "Обсуждение [рендера] 😀")
        let raw = "😀 \(file.rawText) \(command.rawText) \(skill.rawText) \(session) tail"
        let value = ComposerReferencePresentation.attributed(raw, references: [file, command, skill], style: style)
        #expect(value.string == "😀 \u{FFFC} \u{FFFC} \u{FFFC} \u{FFFC} tail")
        let projection = ComposerReferenceProjection(value)
        #expect(projection.rawText == raw)
        #expect(projection.displayRange(NSRange(location: 3, length: file.rawText.utf16.count)) == NSRange(location: 3, length: 1))
        #expect(projection.rawRange(NSRange(location: 3, length: 1)) == NSRange(location: 3, length: file.rawText.utf16.count))
        #expect(projection.rawOffset(value.length) == raw.utf16.count)
        let code = "`\(session)`\n```text\n\(file.rawText)\n```"
        #expect(ComposerReferencePresentation.attributed(code, references: [file], style: style).string == code)
        let invalid = "[missing](sloppy://session?agent=agent)"
        #expect(ComposerReferencePresentation.attributed(invalid, references: [], style: style).string == invalid)
    }

    @Test func nativeInsertsOpenCopyDeleteAndUndoWithoutChangingWireText() async throws {
        AppKitTestAccessibility.enable()
        let model = makeModel()
        let session = ChatSessionReference(agentId: "agent", sessionId: "other-session").markdown(title: "Render discussion")
        let raw = "Check \(file.rawText) with \(skill.rawText) \(command.rawText) \(session)"
        model.composerDraft.text = raw
        model.composerDraft.references = [file, skill, command]
        var opened: ChatComposerReference?
        let host = NSHostingView(rootView: ChatComposerOverlay(viewModel: model, contentWidth: 820,
            composerBottomInset: 16, tabs: [], tabActions: nil)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark)
            .environment(\.chatComposerReferenceOpenHandler, { reference, _ in opened = reference }))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let editor = try #require(descendants(host).compactMap { $0 as? ComposerNSTextView }.first)
        #expect(editor.rawText == raw)
        #expect(editor.inlineReferences.count == 4)
        #expect(!editor.string.contains("sloppy://"))
        let range = NSRange(location: 6, length: 1)
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        let point = editor.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        editor.mouseDown(with: click)
        #expect(opened?.target == file.target)
        #expect(model.composerDraft.text == raw)
        #expect(!model.isSending)

        editor.setSelectedRange(range)
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.string, ComposerNSTextView.referencePasteboardType], owner: nil)
        #expect(editor.writeSelection(to: pasteboard, type: .string))
        #expect(editor.writeSelection(to: pasteboard, type: ComposerNSTextView.referencePasteboardType))
        #expect(pasteboard.string(forType: .string) == file.rawText)
        let data = try #require(pasteboard.data(forType: ComposerNSTextView.referencePasteboardType))
        let copied = try JSONDecoder().decode([ChatComposerReference].self, from: data)
        #expect(copied.count == 1)
        #expect(copied.first?.target == file.target)
        #expect(copied.first?.rawText == file.rawText)
        window.makeFirstResponder(editor)
        editor.deleteBackward(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.composerDraft.text == raw.replacingOccurrences(of: file.rawText, with: ""))
        #expect(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.composerDraft.text == raw)
        #expect(editor.inlineReferences.contains { $0.target == file.target })
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_REFERENCE_SCREENSHOTS"] {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("composer-reference-inserts.png"))
        }
    }

    @Test func draftsAndQueuedMessagesKeepTypedDestinations() {
        let model = makeModel()
        model.syncComposerDraft(toSessionId: "one", projectId: "project", taskId: nil, agentId: "agent")
        model.composerDraft.text = file.rawText
        model.composerDraft.references = [file]
        model.syncComposerDraft(toSessionId: "two", projectId: nil, taskId: nil, agentId: "agent")
        #expect(model.composerDraft.references.isEmpty)
        model.syncComposerDraft(toSessionId: "one", projectId: "project", taskId: nil, agentId: "agent")
        #expect(model.composerDraft.text == file.rawText)
        #expect(model.composerDraft.references == [file])
        var queue = ChatMessageQueue()
        queue.enqueue(content: file.rawText, attachments: [], references: [file])
        #expect(queue.dequeue()?.references == [file])
    }

    @Test func failedSendingPreservesRawMessageAndReferenceMetadata() async throws {
        ReferencePostURLProtocol.capture.store(nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReferencePostURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://reference-post.invalid")),
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        let model = makeModel(api: api)
        model.selectedAgent = .init(id: "agent", displayName: "Agent")
        model.selectedSessionId = "existing"
        model.activeComposerDraftKey = "session:existing"
        let session = ChatSessionReference(agentId: "agent", sessionId: "another").markdown(title: "Discussion")
        let raw = "Check \(file.rawText) and \(session)"
        model.composerDraft.text = raw
        model.composerDraft.references = [file]
        #expect(model.sendMessage(content: raw))
        let deadline = ContinuousClock.now + .seconds(3)
        while model.isSending, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.isSending)
        #expect(model.composerDraft.text == raw)
        #expect(model.composerDraft.references == [file])
        let data = try #require(ReferencePostURLProtocol.capture.load())
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["content"] as? String == raw)
        #expect(!(payload["content"] as? String ?? "").contains("\u{FFFC}"))
        model.closeSession()
    }

    private func makeModel(api: SloppyAPIClient? = nil) -> ChatScreenViewModel {
        let api = api ?? SloppyAPIClient(baseURL: URL(string: "http://reference-fixture.invalid")!)
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            responseNotificationScheduler: ReferenceNotifications(), onOpenSettings: { _ in })
        model.didLoadInitialData = true
        return model
    }
}

@MainActor
private final class ReferenceNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class ReferencePostURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = Capture()
    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var body: Data?
        func store(_ data: Data?) { lock.lock(); defer { lock.unlock() }; body = data }
        func load() -> Data? { lock.lock(); defer { lock.unlock() }; return body }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "reference-post.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.httpMethod == "POST" {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                body = data
            }
            Self.capture.store(body)
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 500,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"error\":\"forced failure\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
