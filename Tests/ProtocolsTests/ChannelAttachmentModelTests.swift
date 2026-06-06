import Foundation
import Testing
@testable import Protocols

@Test
func channelAttachmentInferredTypeUsesMimeTypeAndFilenameFallbacks() {
    #expect(ChannelAttachment.inferredType(mimeType: "image/png", filename: nil) == .image)
    #expect(ChannelAttachment.inferredType(mimeType: "video/mp4", filename: nil) == .video)
    #expect(ChannelAttachment.inferredType(mimeType: "audio/ogg", filename: nil) == .audio)
    #expect(ChannelAttachment.inferredType(mimeType: "application/pdf", filename: nil) == .document)
    #expect(ChannelAttachment.inferredType(mimeType: nil, filename: "photo.HEIC") == .image)
    #expect(ChannelAttachment.inferredType(mimeType: nil, filename: "clip.webm") == .video)
    #expect(ChannelAttachment.inferredType(mimeType: nil, filename: "voice.opus") == .audio)
    #expect(ChannelAttachment.inferredType(mimeType: nil, filename: "notes.md") == .document)
    #expect(ChannelAttachment.inferredType(mimeType: nil, filename: "archive.zip") == .file)
}

@Test
func channelAttachmentPreferredTypeOverridesGenericInference() {
    #expect(ChannelAttachment.inferredType(mimeType: "audio/ogg", filename: "voice.ogg", preferred: .voice) == .voice)
    #expect(ChannelAttachment.inferredType(mimeType: "application/octet-stream", filename: "payload.bin", preferred: .document) == .document)
    #expect(ChannelAttachment.inferredType(mimeType: "image/png", filename: "image.png", preferred: .unknown) == .image)
}

@Test
func channelMessageRequestCodablePreservesAttachments() throws {
    let request = ChannelMessageRequest(
        userId: "discord:user-1",
        content: "see attached",
        topicId: "thread-1",
        attachments: [
            ChannelAttachment(
                id: "att-1",
                type: .image,
                mimeType: "image/png",
                filename: "screenshot.png",
                sizeBytes: 12345,
                url: "https://cdn.example/screenshot.png",
                localPath: "/tmp/screenshot.png",
                platformMetadata: ["platform": "discord", "proxy_url": "https://proxy.example/screenshot.png"]
            )
        ]
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(ChannelMessageRequest.self, from: data)

    #expect(decoded.userId == request.userId)
    #expect(decoded.content == request.content)
    #expect(decoded.topicId == request.topicId)
    #expect(decoded.attachments == request.attachments)
}

@Test
func channelMessageRequestDecodesLegacyPayloadWithoutAttachments() throws {
    let json = #"{"userId":"tg:42","content":"hello","topicId":null}"#.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(ChannelMessageRequest.self, from: json)

    #expect(decoded.userId == "tg:42")
    #expect(decoded.content == "hello")
    #expect(decoded.attachments.isEmpty)
}
