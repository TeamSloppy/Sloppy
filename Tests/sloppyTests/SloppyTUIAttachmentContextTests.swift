import Testing
@testable import sloppy

@Test
func tuiAttachmentFileReferenceDoesNotInlineContent() {
    let block = SloppyTUIAttachmentContext.fileReferenceBlock(
        displayPath: "Sources/App.swift",
        absolutePath: "/tmp/work/Sources/App.swift",
        sizeBytes: 128
    )

    #expect(block.contains("[Attached file: Sources/App.swift]"))
    #expect(block.contains("Path: /tmp/work/Sources/App.swift"))
    #expect(block.contains("Project path: Sources/App.swift"))
    #expect(block.contains("Size: 128 bytes"))
    #expect(block.contains("Content not inlined"))
    #expect(!block.contains("```"))
}
