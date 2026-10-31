import Foundation
import SloppyClientCore
import Testing
import Textual
@testable import SloppyFeatureChat

@Suite("Chat annotations")
struct ChatAnnotationTests {
    @Test("comments stay paired with their quoted selections")
    func quoteComments() throws {
        let quotes = [
            ChatComposerQuote(text: "First\r\nselection", comment: "Change this"),
            ChatComposerQuote(text: "Second selection", comment: "Keep this"),
        ]
        let content = ChatComposerQuote.messageContent("Please apply", quotes: quotes)
        let extracted = try #require(ChatSentAnnotations.extract(from: content))
        #expect(extracted.annotations.map(\.selectedText) == ["First\nselection", "Second selection"])
        #expect(extracted.annotations.map(\.comment) == ["Change this", "Keep this"])
        #expect(extracted.content == "Please apply")
    }

    @Test("points use image coordinates and reject letterbox margins")
    func pointCoordinates() throws {
        let frame = ChatImageRegion.imageFrame(imageSize: CGSize(width: 1600, height: 800),
                                              canvasSize: CGSize(width: 800, height: 600))
        #expect(frame == CGRect(x: 0, y: 100, width: 800, height: 400))
        let region = try #require(ChatImageRegion.selection(
            from: CGPoint(x: 216, y: 197.2), to: CGPoint(x: 216, y: 197.2), imageFrame: frame))
        #expect(region.coordinateDescription == "x: 27.0%, y: 24.3%")
        #expect(ChatImageRegion.selection(from: CGPoint(x: 20, y: 10),
                                          to: CGPoint(x: 40, y: 120), imageFrame: frame) == nil)
    }

    @Test("reverse drags normalize areas and clip at image edges")
    func areaCoordinates() throws {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 200)
        let region = try #require(ChatImageRegion.selection(
            from: CGPoint(x: 400, y: 200), to: CGPoint(x: 0, y: 0), imageFrame: frame))
        #expect(region == ChatImageRegion(x: 0, y: 0, width: 0.75, height: 0.75))
        #expect(ChatImageRegion.selection(from: .zero, to: .zero, imageFrame: .zero) == nil)
        #expect(ChatImageRegion(x: .nan, y: 2, width: .infinity, height: -1)
                == ChatImageRegion(x: 0, y: 1))
    }

    @Test("queued images retain notes and identify duplicate filenames by upload order")
    func queuedImageCoordinates() throws {
        let bytes = Data([1, 2, 3])
        let first = ChatComposerAttachment(name: "screenshot.png", mimeType: "image/png", data: bytes,
            annotations: [.init(region: .init(x: 0.27, y: 0.243), comment: "Fix this button")])
        let second = ChatComposerAttachment(name: "screenshot.png", mimeType: "image/png", data: bytes,
            annotations: [.init(region: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4), comment: "Widen this area")])
        var queue = ChatMessageQueue()
        queue.enqueue(content: "Review", attachments: [first, second])
        let dequeued = queue.dequeue()
        let message = try #require(dequeued)
        #expect(message.attachments == [first, second])
        #expect(message.attachments.map(\.upload.contentBase64) == [bytes.base64EncodedString(), bytes.base64EncodedString()])
        let content = ChatComposerQuote.messageContent(message.content, quotes: message.quotes, attachments: message.attachments)
        let extracted = try #require(ChatSentAnnotations.extract(from: content))
        #expect(extracted.annotations[0].selectedText.contains("attachment 1: screenshot.png"))
        #expect(extracted.annotations[1].selectedText.contains("attachment 2: screenshot.png"))
        #expect(extracted.annotations[0].selectedText.contains("x: 27.0%, y: 24.3%"))
        #expect(extracted.annotations[1].selectedText.contains("width: 30.0%, height: 40.0%"))
        #expect(extracted.annotations.map(\.comment) == ["Fix this button", "Widen this area"])
        #expect(content.hasSuffix("\n\nReview"))
    }

    @Test("editing or deleting a note preserves other selections and image bytes")
    @MainActor
    func editingAnnotations() throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: AnnotationTestNotifications(),
            onOpenSettings: { _ in })
        model.addQuoteToComposer("First")
        model.addQuoteToComposer("Second")
        let firstID = try #require(model.composerQuotes.first?.id)
        model.updateComposerQuote(id: firstID, comment: "First comment")
        #expect(model.composerQuotes.map(\.comment) == ["First comment", ""])
        model.removeComposerQuote(id: firstID)
        #expect(model.composerQuotes.map(\.text) == ["Second"])
        let bytes = Data([1, 2, 3])
        model.attachData(bytes, suggestedName: "screen.png", mimeType: "image/png")
        let attachment = try #require(model.composerAttachments.first)
        let notes = [ChatImageAnnotation(region: .init(x: 0.2, y: 0.3), comment: "Here")]
        model.updateImageAnnotations(id: attachment.id, annotations: notes)
        #expect(model.composerAttachments.first?.annotations == notes)
        #expect(model.composerAttachments.first?.data == bytes)
        model.updateImageAnnotations(id: attachment.id, annotations: [])
        #expect(model.composerAttachments.first?.annotations.isEmpty == true)
    }

    @Test("empty comments are removed only when editing finishes")
    @MainActor
    func emptyCommentRemovesOnlyItsAnnotation() throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: AnnotationTestNotifications(),
            onOpenSettings: { _ in })
        model.addQuoteToComposer("First")
        model.addQuoteToComposer("Second")
        let first = try #require(model.composerQuotes.first?.id)
        let second = try #require(model.composerQuotes.last?.id)
        model.updateComposerQuote(id: first, comment: "Keep this")
        model.updateComposerQuote(id: second, comment: "Original")
        model.updateComposerQuote(id: second, comment: "")
        #expect(model.composerQuotes.count == 2)
        model.updateComposerQuote(id: second, comment: "Replacement")
        model.finishComposerQuoteEditing(id: second)
        #expect(model.composerQuotes.last?.comment == "Replacement")
        model.updateComposerQuote(id: second, comment: " \n \t")
        model.finishComposerQuoteEditing(id: second)
        #expect(model.composerQuotes.map(\.id) == [first])
        #expect(model.composerQuotes.first?.comment == "Keep this")
        #expect(model.pendingComposerQuotes.map(\.id) == [first])
    }

    @Test("source ranges survive draft switching and queued delivery")
    @MainActor
    func anchoredDraftAndQueue() throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: AnnotationTestNotifications(),
            onOpenSettings: { _ in })
        let text = "Текст 👋 и команда"
        let range = (text as NSString).range(of: "👋 и команда")
        let quote = ChatComposerQuote(text: "👋 и команда", comment: "Исправить", source: .init(
            messageID: "message-1", segmentIndex: 2,
            location: TextAnnotationLocation(scope: "root/1", content: text, range: range)))
        model.syncComposerDraft(toSessionId: "one", projectId: nil, taskId: nil, agentId: "agent")
        model.composerQuotes = [quote]
        model.saveActiveComposerDraft()
        model.syncComposerDraft(toSessionId: "two", projectId: nil, taskId: nil, agentId: "agent")
        #expect(model.composerQuotes.isEmpty)
        model.syncComposerDraft(toSessionId: "one", projectId: nil, taskId: nil, agentId: "agent")
        #expect(model.composerQuotes == [quote])
        var queue = ChatMessageQueue()
        queue.enqueue(content: "Apply", attachments: [], quotes: model.composerQuotes)
        #expect(queue.dequeue()?.quotes == [quote])
    }

    @Test("browser annotations preserve page context and never enter a different draft")
    @MainActor
    func browserAnnotationDeliveryAndEditing() throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: AnnotationTestNotifications(),
            onOpenSettings: { _ in })
        model.syncComposerDraft(toSessionId: "one", projectId: nil, taskId: nil, agentId: "agent")
        let receiver = model.makeBrowserAnnotationReceiver()
        let url = try #require(URL(string: "http://localhost:8765/editor"))
        let note = ChatImageAnnotation(region: .init(x: 0.2, y: 0.3, width: 0.1, height: 0.2), comment: "Enlarge",
            browserSource: .init(url: url, title: "Editor", selector: "#create", tag: "button",
                                 elementID: "create", classNames: ["primary", "action"]))
        let attachment = ChatComposerAttachment(name: "Browser annotation.png", mimeType: "image/png",
            data: Data([1, 2, 3]), annotations: [note])
        #expect(receiver(attachment))
        let content = ChatComposerQuote.messageContent("Please fix", quotes: [], attachments: model.composerAttachments)
        #expect(content.contains("Page URL: http://localhost:8765/editor"))
        #expect(content.contains("CSS selector: #create"))
        let sent = try #require(ChatSentAnnotations.extract(from: content)?.annotations.first)
        #expect(sent.source?.contains("HTML tag: button") == true)
        #expect(sent.source?.contains("HTML id: create") == true)
        #expect(sent.source?.contains("HTML classes: primary action") == true)
        var queue = ChatMessageQueue()
        queue.enqueue(content: "Fix", attachments: model.composerAttachments)
        #expect(queue.dequeue()?.attachments.first?.annotations.first?.browserSource == note.browserSource)
        var edited = note
        edited.comment = "Updated"
        model.updateImageAnnotations(id: attachment.id, annotations: [edited])
        #expect(model.composerAttachments.first?.annotations.first?.browserSource == note.browserSource)
        model.updateImageAnnotations(id: attachment.id, annotations: [])
        #expect(model.composerAttachments.isEmpty)
        model.syncComposerDraft(toSessionId: "two", projectId: nil, taskId: nil, agentId: "agent")
        #expect(!receiver(attachment))
        #expect(model.composerAttachments.isEmpty)
    }
}

@MainActor
private final class AnnotationTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
