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
        #expect(decoded.prompt == "Explain this")
        #expect(decoded.target.agentId == "sloppy")
        #expect(decoded.target.sessionId == nil)
        #expect(decoded.userId == "safari_extension")
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
