import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Browser text annotations")
@MainActor
struct BrowserTextAnnotationTests {
    @Test func preservesPageSourceAndDoesNotSendOrReplaceTheDraft() throws {
        let model = makeModel()
        model.useStarterPrompt("Existing draft")
        let url = try #require(URL(string: "https://example.com/article"))
        let quote = ChatComposerQuote(text: "Selected text", comment: "Explain this",
                                      browserSource: .init(url: url, title: "Article"))
        #expect(model.makeBrowserTextAnnotationReceiver()(quote))
        #expect(model.composerQuotes == [quote])
        #expect(model.composerDraft.text == "Existing draft")
        #expect(!model.isSending)
        let content = ChatComposerQuote.messageContent("Question", quotes: model.composerQuotes)
        let sent = try #require(ChatSentAnnotations.extract(from: content))
        #expect(sent.annotations.first?.selectedText == "Selected text")
        #expect(sent.annotations.first?.source == "Page URL: https://example.com/article\nPage title: Article")
        #expect(sent.annotations.first?.comment == "Explain this")
    }

    @Test func rejectsChangedChatAndInvalidSource() throws {
        let model = makeModel()
        let receive = model.makeBrowserTextAnnotationReceiver()
        let acceptedMissingSource = receive(.init(text: "Text"))
        let acceptedFile = receive(.init(text: "Text", browserSource: .init(url: URL(fileURLWithPath: "/tmp/private"), title: "File")))
        #expect(!acceptedMissingSource)
        #expect(!acceptedFile)
        model.selectedSessionId = "different-session"
        let acceptedChangedSession = receive(.init(text: "Text", browserSource: .init(url: URL(string: "https://example.com")!, title: "Page")))
        #expect(!acceptedChangedSession)
        #expect(model.composerQuotes.isEmpty)
    }

    private func makeModel() -> ChatScreenViewModel {
        let api = SloppyAPIClient()
        return ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"), settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), restoresLastSession: false,
            responseNotificationScheduler: BrowserTextAnnotationNotifications(), onOpenSettings: { _ in })
    }
}

@MainActor
private final class BrowserTextAnnotationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
