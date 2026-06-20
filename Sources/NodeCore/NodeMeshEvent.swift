import Foundation
import Protocols

public enum MeshEventType: String, Codable, Sendable, CaseIterable {
    case nodeAnnounced = "node.announced"
    case nodeStatusChanged = "node.status.changed"
    case nodeAliasUpdated = "node.alias.updated"
    case projectCreated = "project.created"
    case projectUpdated = "project.updated"
    case projectMemberAdded = "project.member.added"
    case projectMemberRemoved = "project.member.removed"
    case taskCreated = "task.created"
    case taskAssigned = "task.assigned"
    case taskStatusUpdated = "task.status.updated"
    case messageSent = "message.sent"
    case aclGranted = "acl.granted"
    case aclRevoked = "acl.revoked"
}

public struct MeshEvent: Codable, Sendable, Equatable {
    public var id: String
    public var type: MeshEventType
    public var actorNodeId: String
    public var targetNodeId: String?
    public var projectId: String?
    public var logicalTime: UInt64
    public var wallTime: Date
    public var causalParents: [String]
    public var payload: JSONValue

    public init(
        id: String = "mesh_evt_" + UUID().uuidString,
        type: MeshEventType,
        actorNodeId: String,
        targetNodeId: String? = nil,
        projectId: String? = nil,
        logicalTime: UInt64,
        wallTime: Date = Date(),
        causalParents: [String] = [],
        payload: JSONValue = .object([:])
    ) {
        self.id = id
        self.type = type
        self.actorNodeId = actorNodeId
        self.targetNodeId = targetNodeId
        self.projectId = projectId
        self.logicalTime = logicalTime
        self.wallTime = wallTime
        self.causalParents = causalParents
        self.payload = payload
    }
}

public struct SignedMeshEvent: Codable, Sendable, Equatable {
    public var event: MeshEvent
    public var actorPublicKey: String
    public var signature: String

    public init(event: MeshEvent, actorPublicKey: String, signature: String) {
        self.event = event
        self.actorPublicKey = actorPublicKey
        self.signature = signature
    }
}

public enum MeshEventVerificationError: LocalizedError, Equatable, Sendable {
    case actorMismatch
    case invalidSignature
    case signingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .actorMismatch:
            "Mesh event actor does not match the expected identity."
        case .invalidSignature:
            "Mesh event signature is invalid."
        case .signingFailed(let message):
            "Mesh event signing failed: \(message)"
        }
    }
}

public enum MeshEventSigner {
    public static func sign(_ event: MeshEvent, identity: NodeIdentity) throws -> SignedMeshEvent {
        guard event.actorNodeId == identity.nodeId else {
            throw MeshEventVerificationError.actorMismatch
        }
        do {
            let signature = try NodeIdentityGenerator.sign(
                challenge: signingData(for: event),
                privateKey: identity.privateKey
            )
            return SignedMeshEvent(
                event: event,
                actorPublicKey: identity.publicKey,
                signature: signature
            )
        } catch {
            throw MeshEventVerificationError.signingFailed(error.localizedDescription)
        }
    }

    public static func verify(_ signed: SignedMeshEvent, publicKey: String) throws -> Bool {
        guard signed.actorPublicKey == publicKey else {
            return false
        }
        return NodeIdentityGenerator.verify(
            signature: signed.signature,
            challenge: try signingData(for: signed.event),
            publicKey: publicKey
        )
    }

    public static func signingData(for event: MeshEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(event)
    }
}
