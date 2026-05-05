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
