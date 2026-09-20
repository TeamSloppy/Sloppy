import Foundation
import Testing
import UniformTypeIdentifiers
import SloppyClientCore
@testable import SloppyFeatureChat

@Suite("Chat attachment drops")
@MainActor
struct ChatAttachmentDropTests {
    @Test("directories are attached as ZIP archives with nested paths")
    func acceptsDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-composer-directory-\(UUID().uuidString)", isDirectory: true)
        let nestedDirectory = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("root".utf8).write(to: directory.appendingPathComponent("root.txt"))
        try Data("nested".utf8).write(to: nestedDirectory.appendingPathComponent("child.txt"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachment = try ChatComposerAttachmentLoader.load(
            url: directory,
            maximumSize: 25 * 1_024 * 1_024
        )

        #expect(attachment.name == "\(directory.lastPathComponent).zip")
        #expect(attachment.mimeType == "application/zip")
        #expect(attachment.data.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        #expect(String(decoding: attachment.data, as: UTF8.self).contains("Nested/child.txt"))
        #expect(String(decoding: attachment.data, as: UTF8.self).contains("root.txt"))
        #expect(attachment.data.suffix(22).starts(with: [0x50, 0x4B, 0x05, 0x06]))
    }

    @Test("directory archives respect the attachment size limit")
    func rejectsOversizedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-composer-large-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 512).write(to: directory.appendingPathComponent("large.bin"))
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: ChatComposerAttachmentLoader.LoaderError.self) {
            try ChatComposerAttachmentLoader.load(url: directory, maximumSize: 128)
        }
    }

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

    @Test("prefers image data when a clipboard provider also advertises text")
    func prefersImageRepresentation() async throws {
        let api = SloppyAPIClient()
        let model = ChatScreenViewModel(
            apiClient: api,
            settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false,
            responseNotificationScheduler: DropTestNotifications(),
            onOpenSettings: { _ in }
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let provider = NSItemProvider()
        provider.suggestedName = "clipboard.png"
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("not the attachment".utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(imageData, nil)
            return nil
        }

        #expect(model.attachItemProviders([provider]))
        for _ in 0..<100 where model.composerAttachments.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let attachment = try #require(model.composerAttachments.first)
        #expect(attachment.data == imageData)
        #expect(attachment.mimeType == "image/png")
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
