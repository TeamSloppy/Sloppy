import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Chat computer use activity")
struct ChatComputerUseActivityTests {
    @Test("computer tool calls activate the Mac preview")
    func computerToolCallActivatesMacPreview() throws {
        let activity = try #require(ChatComputerUseEventReducer.reduce(
            current: nil,
            message: toolMessage(
                id: "call-1",
                kind: .toolCall,
                tool: "computer.click",
                status: "started"
            )
        ))

        #expect(activity.source == .computer)
        #expect(activity.phase == .active)
        #expect(activity.title == "Clicking")
    }

    @Test("browser results update the typed browser activity")
    func browserResultUpdatesBrowserActivity() throws {
        let active = try #require(ChatComputerUseEventReducer.reduce(
            current: nil,
            message: toolMessage(
                id: "call-1",
                kind: .toolCall,
                tool: "browser.navigate",
                status: "started"
            )
        ))
        let completed = try #require(ChatComputerUseEventReducer.reduce(
            current: active,
            message: toolMessage(
                id: "result-1",
                kind: .toolResult,
                tool: "browser.navigate",
                status: "done"
            )
        ))

        #expect(completed.source == .browser)
        #expect(completed.phase == .completed)
        #expect(completed.title == "Navigating")
    }

    @Test("failed tool results remain visible as failures")
    func failedToolResultRemainsVisibleAsFailure() throws {
        let activity = try #require(ChatComputerUseEventReducer.reduce(
            current: nil,
            message: toolMessage(
                id: "result-1",
                kind: .toolResult,
                tool: "computer.screenshot",
                status: "failed"
            )
        ))

        #expect(activity.phase == .failed)
    }

    @Test("unrelated tool events do not drive computer use UI")
    func unrelatedToolsDoNotDriveComputerUseUI() {
        let activity = ChatComputerUseEventReducer.reduce(
            current: nil,
            message: toolMessage(
                id: "call-1",
                kind: .toolCall,
                tool: "files.read",
                status: "started"
            )
        )

        #expect(activity == nil)
    }

    private func toolMessage(
        id: String,
        kind: ChatMessageSegmentKind,
        tool: String,
        status: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .system,
            segments: [
                ChatMessageSegment(
                    kind: kind,
                    title: tool,
                    status: status
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
