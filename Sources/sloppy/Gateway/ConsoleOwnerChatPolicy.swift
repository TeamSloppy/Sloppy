import Foundation
import SloppyConsoleProtocol

/// Personal owner grants may operate chats without permission to administer the Core.
/// Project-scoped and organization grants continue through the existing project policy.
enum ConsoleOwnerChatPolicy {
    static func permissions(method: HTTPRouteMethod, segments: [String], body: Data?) -> Set<InstancePermission>? {
        guard segments.first == "v1" else { return nil }
        var required: Set<InstancePermission> = [.read, .runAgents]
        if segments == ["v1", "auth", "me"], method == .get { return required }
        if segments == ["v1", "voice", "transcriptions"], method == .post { return required.union([.write]) }
        guard segments.count >= 2, segments[1] == "agents" else { return nil }
        if segments.count == 2, method == .get { return required }
        guard segments.count >= 4, segments[3] == "sessions" else { return nil }
        if segments.count == 4, method == .get || method == .post {
            if method == .post { required.insert(.write) }; return required
        }
        if segments.count == 5, method == .get { return required }
        guard segments.count == 6 else { return nil }
        if method == .get, segments[5] == "ws" || segments[5] == "stream" { return required }
        if method == .post, segments[5] == "messages" { return required.union([.write]) }
        if method == .post, segments[5] == "control",
           let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           json["action"] as? String == "interrupt" { return required.union([.write]) }
        return nil
    }

    static func matchesOwner(binding: InstanceBinding?, accountID: UUID, instanceID: UUID, organizationID: UUID?, projectIDs: Set<String>) -> Bool {
        guard let binding, binding.status == .active, binding.id == instanceID, binding.ownerID == accountID,
              organizationID == nil, projectIDs.isEmpty else { return false }
        return true
    }
}

extension CoreService {
    func allowsConsoleOwnerChat(_ context: ConsoleAuthorizationContext, request: HTTPRequest) async -> Bool {
        guard context.expiresAt > Date(), ConsoleOwnerChatPolicy.matchesOwner(binding: await consoleTrustStore?.binding(),
            accountID: context.accountID, instanceID: context.instanceID, organizationID: context.organizationID, projectIDs: context.projectIDs),
            let required = ConsoleOwnerChatPolicy.permissions(method: request.method, segments: request.segments, body: request.body) else { return false }
        return required.isSubset(of: context.permissions)
    }
}
