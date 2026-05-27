import Testing
@testable import sloppy

@Test
func tuiSelectionNormalizesForwardAndBackwardDrags() {
    var state = SloppyTUISelectionState()
    state.press(at: .init(row: 4, column: 8))
    state.drag(to: .init(row: 2, column: 3))

    #expect(state.activeRange == SloppyTUITextSelectionRange(
        start: .init(row: 2, column: 3),
        end: .init(row: 4, column: 9)
    ))

    _ = state.release()
    #expect(state.activeRange == nil)
}

@Test
func tuiSelectionCopiesPlainVisibleTextWithoutAnsiOrPadding() {
    let lines = [
        "\u{001B}[31m012345\u{001B}[0m   ",
        "abcdef      ",
        "\u{001B}[7muvwxyz\u{001B}[0m",
    ]
    let range = SloppyTUITextSelectionRange(
        start: .init(row: 0, column: 2),
        end: .init(row: 2, column: 3)
    )

    #expect(SloppyTUISelectionRenderer.selectedText(lines: lines, range: range) == "2345\nabcdef\nuvw")
}

@Test
func tuiSelectionOverlayKeepsPlainTextAndHighlightsSelectedCharacters() {
    let lines = ["hello world"]
    let range = SloppyTUITextSelectionRange(
        start: .init(row: 0, column: 6),
        end: .init(row: 0, column: 11)
    )

    let highlighted = SloppyTUISelectionRenderer.applySelectionOverlay(lines: lines, range: range)

    #expect(SloppyTUISelectionRenderer.stripANSI(highlighted[0]) == "hello world")
    #expect(highlighted[0].contains("\u{001B}[7mw\u{001B}[0m"))
}

@Test
func tuiHitRegionOverlayKeepsPlainTextAndHighlightsClickableCharacters() {
    let lines = ["alpha beta gamma"]
    let region = SloppyTUIHitRegion(
        row: 0,
        startColumn: 6,
        endColumn: 10,
        action: .commandPalette(index: 1)
    )

    let highlighted = SloppyTUISelectionRenderer.applyHitRegionOverlay(lines: lines, region: region)

    #expect(SloppyTUISelectionRenderer.stripANSI(highlighted[0]) == "alpha beta gamma")
    #expect(highlighted[0].contains("\u{001B}[7mb\u{001B}[0m"))
}

@Test
func tuiHitRegionMatchesOnlyBoundedCells() {
    let region = SloppyTUIHitRegion(
        row: 3,
        startColumn: 4,
        endColumn: 10,
        action: .commandPalette(index: 2)
    )

    #expect(region.contains(.init(row: 3, column: 4)))
    #expect(region.contains(.init(row: 3, column: 9)))
    #expect(!region.contains(.init(row: 3, column: 10)))
    #expect(!region.contains(.init(row: 2, column: 4)))
}
