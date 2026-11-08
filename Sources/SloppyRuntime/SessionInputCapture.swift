import Foundation
import Protocols

public enum SessionInputCapture {
    public static func fingerprint(_ request: AgentSessionPostMessageRequest, peerOrigin: AgentSessionPeerOrigin?,
        uiSubmission: AgentUISubmission? = nil, uiSnapshot: AgentUISurfaceSnapshot? = nil,
        sourceRequest: AgentSessionPostMessageRequest? = nil) throws -> String {
        var normalized = request
        normalized.clientMessageId = nil
        var inline: [JSONValue] = []
        for index in request.attachments.indices {
            let bytes = try decoded(request.attachments[index])
            inline.append(.object(["present": .bool(request.attachments[index].contentBase64 != nil),
                "sha256": bytes.map { .string(ContentDigest.sha256($0)) } ?? .null]))
            normalized.attachments[index].contentBase64 = nil
        }
        guard var object = try JSONValueCoder.encode(normalized).asObject else { throw invalid() }
        object["inlineAttachments"] = .array(inline)
        if let peerOrigin { object["peerOrigin"] = try JSONValueCoder.encode(peerOrigin) }
        if let uiSubmission { object["uiSubmission"] = try JSONValueCoder.encode(uiSubmission) }
        if let uiSnapshot { object["uiSnapshot"] = try JSONValueCoder.encode(uiSnapshot) }
        if var sourceRequest {
            sourceRequest.clientMessageId = nil
            for index in sourceRequest.attachments.indices { sourceRequest.attachments[index].contentBase64 = nil }
            object["sourceRequest"] = try JSONValueCoder.encode(sourceRequest)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return "v2:" + ContentDigest.sha256(try encoder.encode(JSONValue.object(object)))
    }

    public static func capture(_ request: AgentSessionPostMessageRequest, messageID: String,
        attachments: [AgentAttachment], peerOrigin: AgentSessionPeerOrigin?,
        uiSubmission: AgentUISubmission? = nil, uiSnapshot: AgentUISurfaceSnapshot? = nil,
        sourceRequest: AgentSessionPostMessageRequest? = nil) throws -> AgentInputContext {
        guard attachments.count == request.attachments.count else { throw invalid() }
        var normalized = request
        normalized.clientMessageId = messageID
        var bindings: [AgentInputAttachment] = []
        for index in request.attachments.indices {
            let upload = request.attachments[index]
            let bytes = try decoded(upload)
            bindings.append(.init(attachment: attachments[index], hadInlineData: upload.contentBase64 != nil,
                sha256: bytes.map(ContentDigest.sha256)))
            normalized.attachments[index].contentBase64 = nil
        }
        let source: AgentSessionPostMessageRequest?
        if var original = sourceRequest {
            original.clientMessageId = messageID
            for index in original.attachments.indices { original.attachments[index].contentBase64 = nil }
            source = original
        } else {
            source = nil
        }
        return .init(request: normalized, attachments: bindings, peerOrigin: peerOrigin,
            uiSubmission: uiSubmission, uiSnapshot: uiSnapshot, sourceRequest: source)
    }

    public static func materialize(_ context: AgentInputContext, store: AgentSessionFileStore,
        agentID: String, sessionID: String) throws -> AgentSessionPostMessageRequest {
        guard context.request.attachments.count == context.attachments.count else { throw invalid() }
        var request = context.request
        for index in context.attachments.indices {
            let binding = context.attachments[index]
            if binding.hadInlineData {
                let bytes = try store.readInputAttachment(agentID: agentID, sessionID: sessionID, attachment: binding.attachment)
                guard ContentDigest.sha256(bytes) == binding.sha256 else { throw invalid() }
                request.attachments[index].contentBase64 = bytes.base64EncodedString()
            } else {
                guard binding.sha256 == nil, binding.attachment.relativePath == nil else { throw invalid() }
                request.attachments[index].contentBase64 = nil
            }
        }
        return request
    }

    private static func decoded(_ upload: AgentAttachmentUpload) throws -> Data? {
        guard let encoded = upload.contentBase64 else { return nil }
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]) else { throw invalid() }
        return data
    }

    private static func invalid() -> AgentSessionFileStore.StoreError { .invalidPayload }
}
