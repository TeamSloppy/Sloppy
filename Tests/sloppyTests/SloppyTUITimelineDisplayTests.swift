import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func tuiDisplayCollapsesInlineAttachedFileContent() {
    let raw = """
    please inspect @Sources/sloppy/TUI/SloppyTUIApp.swift

    [Attached file: Sources/sloppy/TUI/SloppyTUIApp.swift]
    ```
    line one
    line two
    ```
    """

    let display = SloppyTUITimelineDisplay.messageText(role: .user, text: raw)

    #expect(display.contains("please inspect"))
    #expect(display.contains("[Attached file: Sources/sloppy/TUI/SloppyTUIApp.swift]"))
    #expect(display.contains("hidden in TUI"))
    #expect(!display.contains("line one"))
    #expect(!display.contains("line two"))
}

@Test
func tuiDisplayLeavesAssistantMessagesUntouched() {
    let raw = "[Attached file: demo.swift]\n```\nlet value = 1\n```"

    let display = SloppyTUITimelineDisplay.messageText(role: .assistant, text: raw)

    #expect(display == raw)
}

@Test
func tuiToolCallDisplayHumanizesFileRead() {
    let display = SloppyTUITimelineDisplay.toolCallDisplay(
        tool: "files.read",
        arguments: [
            "path": .string("yx360-promozavr-debug-screen/src/debug/kotlin/com/yx360/promozavr/debug/ui/PromozavrDebugScreen.kt"),
            "offset": .number(1),
            "maxBytes": .number(320),
        ]
    )

    #expect(display.summary == "Read yx360-promozavr-debug-screen/src/debug/kotlin/com/yx360/promozavr/debug/ui/PromozavrDebugScreen.kt [offset=1, limit=320]")
    #expect(display.details == nil)
}

@Test
func tuiRuntimeExecSummaryEscapesMultilineCommands() {
    let display = SloppyTUITimelineDisplay.toolCallDisplay(
        tool: "runtime.exec",
        arguments: [
            "command": .string("bash"),
            "arguments": .array([
                .string("-lc"),
                .string("python3 - <<'PY'\nfrom pathlib import Path\np = Path('/tmp/demo.txt')\nPY"),
            ]),
        ]
    )

    #expect(display.summary?.contains("\n") == false)
    #expect(display.summary?.contains(#"\nfrom pathlib import Path"#) == true)
    #expect(display.details?.contains("from pathlib import Path") == true)
}

@Test
func tuiToolCallDisplayHumanizesGrep() {
    let display = SloppyTUITimelineDisplay.toolCallDisplay(
        tool: "files.grep",
        arguments: [
            "query": .string("SwipeRefresh|pullRefresh"),
            "path": .string("."),
            "regex": .bool(true),
        ]
    )

    #expect(display.summary == #"Grep "SwipeRefresh|pullRefresh" in ."#)
}

@Test
func tuiToolResultTitleIncludesGrepMatchCount() {
    let title = SloppyTUITimelineDisplay.toolResultTitle(
        AgentToolResultEvent(
            tool: "files.grep",
            ok: true,
            data: .object(["matchesCount": .number(11)])
        )
    )

    #expect(title == "Grep (11 matches)")
}

@Test
func tuiToolApprovalDisplayShowsFilesEditDiffPreview() throws {
    let approval = ToolApprovalRecord(
        id: "approval-edit",
        agentId: "agent-1",
        sessionId: "session-1",
        tool: "files.edit",
        arguments: [
            "path": .string("Classes/Platform/DiskPushNotifications.swift"),
            "search": .string("guard let filter = isIncluded else {\n    continuation.finish()\n    return\n}"),
            "replace": .string("guard let payload = Self.decodePayload(Payload.self, from: rawData, decoder: decoder) else {\n    continue\n}")
        ],
        expiresAt: Date(timeIntervalSince1970: 200)
    )

    let display = try #require(SloppyTUITimelineDisplay.toolApprovalDisplay(approval))

    #expect(display.contains("## Edit file"))
    #expect(display.contains("Classes/Platform/DiskPushNotifications.swift"))
    #expect(display.contains("Added 3 lines, removed 4 lines"))
    #expect(display.contains("```diff"))
    #expect(display.contains("-guard let filter = isIncluded else {"))
    #expect(display.contains("+guard let payload = Self.decodePayload"))
}
