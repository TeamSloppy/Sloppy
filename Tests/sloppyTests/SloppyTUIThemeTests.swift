import Testing
@testable import sloppy

@Test
func composerHighlightsSlashCommandsAndAtPaths() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/help /123_skill @Sources/sloppy/TUI/SloppyTUITheme.swift",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;103;232;249m"))
    #expect(highlighted[1].contains("\u{001B}[38;2;250;204;21m"))
    #expect(stripANSI(highlighted[1]) == lines[1])
}

@Test
func composerDoesNotHighlightAutocompleteAfterEditorBorder() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/help",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/model  Switch model",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;103;232;249m"))
    #expect(highlighted[3] == lines[3])
}

private func stripANSI(_ line: String) -> String {
    var result = ""
    var index = line.startIndex
    while index < line.endIndex {
        if line[index] == "\u{001B}" {
            index = ansiEscapeEnd(in: line, from: index)
            continue
        }
        result.append(line[index])
        index = line.index(after: index)
    }
    return result
}

private func ansiEscapeEnd(in line: String, from start: String.Index) -> String.Index {
    let next = line.index(after: start)
    guard next < line.endIndex else {
        return next
    }

    if line[next] == "[" {
        var index = line.index(after: next)
        while index < line.endIndex {
            let scalar = line[index].unicodeScalars.first?.value ?? 0
            index = line.index(after: index)
            if scalar >= 0x40 && scalar <= 0x7E {
                return index
            }
        }
        return line.endIndex
    }

    return line.index(after: next)
}
