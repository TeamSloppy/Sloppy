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

@Test
func tuiImagePathDetectionIsCaseInsensitive() {
    #expect(SloppyTUIAttachmentContext.isImagePath("/tmp/CAT.PNG"))
    #expect(SloppyTUIAttachmentContext.isImagePath("file:///tmp/cat.webp"))
    #expect(SloppyTUIAttachmentContext.isImagePath("Assets/gallery/cat.heic"))
    #expect(!SloppyTUIAttachmentContext.isImagePath("Sources/App.swift"))
}

@Test
func tuiImageMarkerUsesFilenameOnly() {
    #expect(SloppyTUIAttachmentContext.imageMarker(forPath: "/tmp/screenshots/cat.png") == "[Image cat.png]")
    #expect(SloppyTUIAttachmentContext.imageMarker(forPath: "file:///tmp/screenshots/CAT.PNG") == "[Image CAT.PNG]")
    #expect(SloppyTUIAttachmentContext.imageMarker(filename: "") == "[Image]")
}
