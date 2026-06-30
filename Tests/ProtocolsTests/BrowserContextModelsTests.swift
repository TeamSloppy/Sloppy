import Foundation
import Protocols
import Testing

@Suite("Browser context protocol models")
struct BrowserContextModelsTests {
    @Test("browser context message request round-trips with defaults")
    func browserContextMessageRequestRoundTripsWithDefaults() throws {
        let request = BrowserContextMessageRequest(
            page: BrowserContextPage(
                url: "https://example.com/article",
                title: "Example Article"
            ),
            selection: BrowserContextSelection(text: "Selected text"),
            prompt: "Explain this"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(BrowserContextMessageRequest.self, from: data)

        #expect(decoded.source == "safari_extension")
        #expect(decoded.page.url == "https://example.com/article")
        #expect(decoded.page.title == "Example Article")
        #expect(decoded.selection.text == "Selected text")
        #expect(decoded.context == nil)
        #expect(decoded.prompt == "Explain this")
        #expect(decoded.target.agentId == "sloppy")
        #expect(decoded.target.sessionId == nil)
        #expect(decoded.attachments.isEmpty)
        #expect(decoded.userId == "safari_extension")
    }

    @Test("browser context message request decodes old payloads without attachments")
    func browserContextMessageRequestDecodesOldPayloadsWithoutAttachments() throws {
        let data = Data(
            """
            {
              "source": "safari_extension",
              "page": { "url": "https://example.com/article", "title": "Example Article" },
              "selection": { "text": "Selected text" },
              "prompt": "Explain this",
              "target": { "agentId": "sloppy" },
              "userId": "safari_extension"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(BrowserContextMessageRequest.self, from: data)

        #expect(decoded.attachments.isEmpty)
        #expect(decoded.target.agentId == "sloppy")
        #expect(decoded.userId == "safari_extension")
    }

    @Test("browser context message request preserves browser page snapshot")
    func browserContextMessageRequestPreservesBrowserPageSnapshot() throws {
        let request = BrowserContextMessageRequest(
            page: BrowserContextPage(url: "https://example.com/article"),
            selection: BrowserContextSelection(text: ""),
            prompt: "Summarize this",
            browser: BrowserContextBrowser(
                pageSnapshot: .object([
                    "text": .string("Article body"),
                    "elements": .array([
                        .object(["selector": .string("#buy")])
                    ])
                ])
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(BrowserContextMessageRequest.self, from: data)

        #expect(decoded.browser?.pageSnapshot == request.browser?.pageSnapshot)
    }

    @Test("browser context message request round-trips project and task references")
    func browserContextMessageRequestRoundTripsContextReferences() throws {
        let request = BrowserContextMessageRequest(
            page: BrowserContextPage(url: "https://example.com/article"),
            selection: BrowserContextSelection(text: "Selected text"),
            prompt: "Explain this",
            context: BrowserContextMessageContext(
                projectReference: "PROMOZAVR",
                taskReference: "123"
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(BrowserContextMessageRequest.self, from: data)

        #expect(decoded.context?.projectReference == "PROMOZAVR")
        #expect(decoded.context?.taskReference == "123")
    }

    @Test("browser context message response round-trips")
    func browserContextMessageResponseRoundTrips() throws {
        let response = BrowserContextMessageResponse(
            sessionId: "session-1",
            messageId: "message-1",
            status: "completed",
            text: "Agent response"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(BrowserContextMessageResponse.self, from: data)

        #expect(decoded.sessionId == "session-1")
        #expect(decoded.messageId == "message-1")
        #expect(decoded.status == "completed")
        #expect(decoded.text == "Agent response")
    }
}
