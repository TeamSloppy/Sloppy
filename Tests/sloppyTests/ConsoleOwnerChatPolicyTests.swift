import Foundation
import SloppyConsoleProtocol
import Testing
@testable import sloppy

@Suite struct ConsoleOwnerChatPolicyTests {
    @Test func exactChatRoutesRequireReadRunAndWriteForMutations() {
        for path in ["/v1/auth/me", "/v1/agents", "/v1/agents/a/sessions", "/v1/agents/a/sessions/s", "/v1/agents/a/sessions/s/ws", "/v1/agents/a/sessions/s/stream"] {
            #expect(ConsoleOwnerChatPolicy.permissions(method: .get, segments: path.split(separator: "/").map(String.init), body: nil) == [.read, .runAgents])
        }
        for path in ["/v1/agents/a/sessions", "/v1/agents/a/sessions/s/messages", "/v1/voice/transcriptions", "/v1/agents/a/sessions/s/control"] {
            #expect(ConsoleOwnerChatPolicy.permissions(method: .post, segments: path.split(separator: "/").map(String.init), body: Data("{\"action\":\"interrupt\"}".utf8)) == [.read, .write, .runAgents])
        }
        for (method, path) in [(HTTPRouteMethod.post, "/v1/agents"), (.delete, "/v1/agents/a"), (.get, "/v1/config"), (.put, "/v1/agents/a/config"), (.get, "/v1/dashboard/terminal/ws"), (.post, "/v1/agents/a/sessions/s/input-requests/r/answer")] {
            #expect(ConsoleOwnerChatPolicy.permissions(method: method, segments: path.split(separator: "/").map(String.init), body: nil) == nil)
        }
        #expect(ConsoleOwnerChatPolicy.permissions(method: .post, segments: ["v1", "agents", "a", "sessions", "s", "control"], body: Data("{\"action\":\"approve\"}".utf8)) == nil)
    }

    @Test func onlyActiveBoundOwnerPersonalUnscopedGrantMatches() {
        let owner = UUID(), instance = UUID()
        var binding = InstanceBinding(id: instance, ownerID: owner, spaceID: UUID(), name: "test", authorityPublicKey: Data(), hostDeviceID: UUID(), status: .active)
        func matches(_ value: InstanceBinding?, account: UUID? = nil, id: UUID? = nil, org: UUID? = nil, projects: Set<String> = []) -> Bool {
            ConsoleOwnerChatPolicy.matchesOwner(binding: value, accountID: account ?? owner, instanceID: id ?? instance, organizationID: org, projectIDs: projects)
        }
        #expect(matches(binding))
        #expect(!matches(nil)); #expect(!matches(binding, account: UUID())); #expect(!matches(binding, id: UUID()))
        #expect(!matches(binding, org: UUID())); #expect(!matches(binding, projects: ["p"]))
        binding.status = .revoked; #expect(!matches(binding))
    }
}
