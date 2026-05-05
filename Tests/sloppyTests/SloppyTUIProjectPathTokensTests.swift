import Testing
@testable import sloppy

@Test
func projectPathTokenStopsAfterUnescapedSpace() {
    let token = SloppyTUIProjectPathTokens.tokenBeforeCursor(
        lines: ["please inspect @Sources/App.swift now"],
        cursorLine: 0,
        cursorColumn: "please inspect @Sources/App.swift now".count
    )

    #expect(token == nil)
}

@Test
func projectPathTokenKeepsBackslashEscapedSpace() throws {
    let line = "please inspect @Android\\ Studio/Main.swift"
    let token = try #require(SloppyTUIProjectPathTokens.tokenBeforeCursor(
        lines: [line],
        cursorLine: 0,
        cursorColumn: line.count
    ))

    #expect(token.rawToken == "@Android\\ Studio/Main.swift")
    #expect(token.path == "Android Studio/Main.swift")
}

@Test
func projectPathTokenKeepsSpaceBeforeBackslash() throws {
    let line = "please inspect @Android \\Studio/Main.swift"
    let token = try #require(SloppyTUIProjectPathTokens.tokenBeforeCursor(
        lines: [line],
        cursorLine: 0,
        cursorColumn: line.count
    ))

    #expect(token.rawToken == "@Android \\Studio/Main.swift")
    #expect(token.path == "Android Studio/Main.swift")
}

@Test
func projectPathTokenExtractorFindsEscapedAttachmentPaths() {
    let paths = SloppyTUIProjectPathTokens.attachmentPaths(
        in: "read @Android\\ Studio/Main.swift and @Sources/App.swift done"
    )

    #expect(paths == ["Android Studio/Main.swift", "Sources/App.swift"])
}
