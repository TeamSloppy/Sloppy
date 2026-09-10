import Foundation
import Testing
import UniformTypeIdentifiers
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("Chat attachment drops")
@MainActor
struct ChatAttachmentDropTests {
    @Test("accepts non-image resources with their original bytes and name")
    func acceptsDocument() async throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(
            apiClient: api,
            settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false,
            responseNotificationScheduler: DropTestNotifications(),
            onOpenSettings: { _ in }
        )
        let data = Data("%PDF-test attachment".utf8)
        let provider = NSItemProvider()
        provider.suggestedName = "document.pdf"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }

        #expect(model.attachItemProviders([provider]))
        for _ in 0..<100 where model.composerAttachments.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let attachment = try #require(model.composerAttachments.first)
        #expect(attachment.data == data)
        #expect(attachment.name == "document.pdf")
        #expect(attachment.mimeType == "application/pdf")
    }

    @Test("rejects providers without loadable resources")
    func rejectsUnsupportedProvider() {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(
            apiClient: api,
            settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false,
            responseNotificationScheduler: DropTestNotifications(),
            onOpenSettings: { _ in }
        )
        #expect(!model.attachItemProviders([NSItemProvider()]))
        #expect(model.composerAttachments.isEmpty)
    }
}


@MainActor
private final class DropTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
