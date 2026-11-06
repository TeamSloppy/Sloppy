import Foundation

public enum AgentInputDisposition: String, Codable, Sendable, Equatable {
    case queued, admitted, cancelled, failed
    case recordedOnly = "recorded_only"
}

/// Receiving a message and delivering its receipt are independent of executing it.
public enum AgentInputDelivery: String, Codable, Sendable, Equatable {
    case pending, delivered
}

/// The admission generation is immutable; later cancellation generations belong to runtime metadata.
public struct AgentInputOwner: Codable, Sendable, Equatable {
    public var runId: String
    public var userTurnId: String
    public var generation: Int

    public init(runId: String, userTurnId: String, generation: Int) {
        self.runId = runId
        self.userTurnId = userTurnId
        self.generation = generation
    }
}

public struct AgentInputAttachment: Codable, Sendable, Equatable {
    public var attachment: AgentAttachment
    public var hadInlineData: Bool
    public var sha256: String?

    public init(attachment: AgentAttachment, hadInlineData: Bool, sha256: String? = nil) {
        self.attachment = attachment
        self.hadInlineData = hadInlineData
        self.sha256 = sha256
    }
}

/// Stored once. Upload metadata stays in request; attachment bytes live in ordered, digest-bound blobs.
public struct AgentInputContext: Codable, Sendable, Equatable {
    public var request: AgentSessionPostMessageRequest
    /// Original accepted submission when command or peer-scope preparation changed execution fields.
    public var sourceRequest: AgentSessionPostMessageRequest?
    public var attachments: [AgentInputAttachment]
    public var peerOrigin: AgentSessionPeerOrigin?
    public var uiSubmission: AgentUISubmission?
    public var uiSnapshot: AgentUISurfaceSnapshot?

    public init(request: AgentSessionPostMessageRequest, attachments: [AgentInputAttachment] = [],
        peerOrigin: AgentSessionPeerOrigin? = nil, uiSubmission: AgentUISubmission? = nil,
        uiSnapshot: AgentUISurfaceSnapshot? = nil, sourceRequest: AgentSessionPostMessageRequest? = nil) {
        self.request = request
        self.sourceRequest = sourceRequest
        self.attachments = attachments
        self.peerOrigin = peerOrigin
        self.uiSubmission = uiSubmission
        self.uiSnapshot = uiSnapshot
    }
}

/// A journal-level envelope: queued messages have no execution owner or runtime metadata.
public struct AgentInputTransition: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var messageId: String
    public var fingerprint: String
    public var disposition: AgentInputDisposition
    public var delivery: AgentInputDelivery
    public var owner: AgentInputOwner?
    public var context: AgentInputContext?

    public init(schemaVersion: Int = 1, messageId: String, fingerprint: String,
        disposition: AgentInputDisposition, delivery: AgentInputDelivery = .pending,
        owner: AgentInputOwner? = nil, context: AgentInputContext? = nil) {
        self.schemaVersion = schemaVersion
        self.messageId = messageId
        self.fingerprint = fingerprint
        self.disposition = disposition
        self.delivery = delivery
        self.owner = owner
        self.context = context
    }
}
