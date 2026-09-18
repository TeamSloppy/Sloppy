import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Chat conversation navigator")
struct ChatConversationNavigatorTests {
    @Test("builds one waypoint per user turn and attaches assistant previews")
    func buildsWaypointsFromTypedRoles() {
        let messages = [
            message(id: "orphan", role: .assistant, text: "Earlier answer"),
            message(id: "user-1", role: .user, text: "  Fix   the sidebar\nspacing  "),
            message(id: "system-1", role: .system, text: "Running tools"),
            message(id: "assistant-1", role: .assistant, text: "I updated the spacing."),
            message(id: "assistant-2", role: .assistant, text: "The focused tests pass."),
            message(id: "user-2", role: .user, text: "Add keyboard navigation"),
        ]

        let waypoints = ChatConversationWaypoint.build(from: messages)

        #expect(waypoints.count == 2)
        #expect(waypoints[0].id == "user-1")
        #expect(waypoints[0].targetItemID == "entry:message:user-1")
        #expect(waypoints[0].title == "Fix the sidebar spacing")
        #expect(waypoints[0].responsePreview == "I updated the spacing. The focused tests pass.")
        #expect(waypoints[1].responsePreview == nil)
    }

    @Test("keeps previews bounded and provides a fallback for non-text user turns")
    func boundsPreviews() {
        let longResponse = String(repeating: "result ", count: 100)
        let messages = [
            ChatMessage(id: "user", role: .user, segments: [.init(kind: .attachment)]),
            message(id: "assistant", role: .assistant, text: longResponse),
        ]

        let waypoint = ChatConversationWaypoint.build(from: messages)[0]

        #expect(waypoint.title == "User message")
        #expect(waypoint.responsePreview?.count == 361)
        #expect(waypoint.responsePreview?.hasSuffix("…") == true)
    }

    private func message(id: String, role: ChatMessageRole, text: String) -> ChatMessage {
        ChatMessage(id: id, role: role, segments: [.init(kind: .text, text: text)])
    }
}
