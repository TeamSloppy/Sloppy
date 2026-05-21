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
