import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct SloppyTUIScreenCell: Equatable {
    var row: Int
    var column: Int
}

struct SloppyTUITextSelectionRange: Equatable {
    var start: SloppyTUIScreenCell
    var end: SloppyTUIScreenCell
}

struct SloppyTUISelectionState: Equatable {
    private(set) var anchor: SloppyTUIScreenCell?
    private(set) var focus: SloppyTUIScreenCell?
    private(set) var isDragging = false

    var activeRange: SloppyTUITextSelectionRange? {
        guard let anchor, let focus, isDragging else { return nil }
        return Self.normalizedRange(anchor: anchor, focus: focus)
    }

    mutating func press(at cell: SloppyTUIScreenCell) {
        anchor = cell
        focus = cell
        isDragging = false
    }

    mutating func drag(to cell: SloppyTUIScreenCell) {
        guard let anchor else { return }
        focus = cell
        isDragging = anchor != cell
    }

    mutating func release() -> SloppyTUITextSelectionRange? {
        defer { clear() }
        return activeRange
    }

    mutating func clear() {
        anchor = nil
        focus = nil
        isDragging = false
    }

    static func normalizedRange(anchor: SloppyTUIScreenCell, focus: SloppyTUIScreenCell) -> SloppyTUITextSelectionRange {
        let start: SloppyTUIScreenCell
        let end: SloppyTUIScreenCell
        if anchor.row < focus.row || (anchor.row == focus.row && anchor.column <= focus.column) {
            start = anchor
            end = .init(row: focus.row, column: focus.column + 1)
        } else {
            start = focus
            end = .init(row: anchor.row, column: anchor.column + 1)
        }
        return .init(start: start, end: end)
    }
}

enum SloppyTUIHitAction: Equatable {
    case activePicker(index: Int)
    case commandPalette(index: Int)
    case projectFile(index: Int)
    case projectTask(index: Int)
    case reasoningEffort(index: Int)
    case scrollbackMode(index: Int)
    case sessionList(index: Int)
    case toggleTranscript
    case openSubSession(String)
}

struct SloppyTUIHitRegion: Equatable {
    var row: Int
    var startColumn: Int
    var endColumn: Int
    var action: SloppyTUIHitAction

    func contains(_ cell: SloppyTUIScreenCell) -> Bool {
        cell.row == row && cell.column >= startColumn && cell.column < endColumn
    }
}

enum SloppyTUIScrollTarget: Equatable {
    case activePicker
    case commandPalette
    case projectFile
    case projectTask
    case sessionList
}

struct SloppyTUIScrollRegion: Equatable {
    var startRow: Int
    var endRow: Int
    var startColumn: Int
    var endColumn: Int
    var target: SloppyTUIScrollTarget

    func contains(_ cell: SloppyTUIScreenCell) -> Bool {
        cell.row >= startRow
            && cell.row < endRow
            && cell.column >= startColumn
            && cell.column < endColumn
    }
}

enum SloppyTUIClipboard {
    static func copy(_ text: String) -> Bool {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
        #else
        _ = text
        return false
        #endif
    }
}

enum SloppyTUISelectionRenderer {
    static func selectedText(lines: [String], range: SloppyTUITextSelectionRange) -> String {
        let startRow = max(0, min(range.start.row, lines.count))
        let endRow = max(0, min(range.end.row, lines.count - 1))
        guard startRow <= endRow, lines.indices.contains(startRow) else { return "" }

        var selected: [String] = []
        for row in startRow...endRow {
            let plain = stripANSI(lines[row])
            let startColumn = row == range.start.row ? range.start.column : 0
            let endColumn = row == range.end.row ? range.end.column : plain.count
            selected.append(slice(plain, startColumn: startColumn, endColumn: endColumn).trimmedRenderPadding())
        }
        return selected.joined(separator: "\n")
    }

    static func applySelectionOverlay(lines: [String], range: SloppyTUITextSelectionRange?) -> [String] {
        guard let range else { return lines }
        return lines.enumerated().map { row, line in
            guard row >= range.start.row, row <= range.end.row else { return line }
            let plain = stripANSI(line)
            let startColumn = row == range.start.row ? range.start.column : 0
            let endColumn = row == range.end.row ? range.end.column : plain.count
            return highlightedPlainLine(plain, startColumn: startColumn, endColumn: endColumn)
        }
    }

    static func applyHitRegionOverlay(lines: [String], region: SloppyTUIHitRegion?) -> [String] {
        guard let region, lines.indices.contains(region.row) else { return lines }
        return lines.enumerated().map { row, line in
            guard row == region.row else { return line }
            return highlightedPlainLine(
                stripANSI(line),
                startColumn: region.startColumn,
                endColumn: region.endColumn
            )
        }
    }

    static func stripANSI(_ line: String) -> String {
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

    private static func highlightedPlainLine(_ line: String, startColumn: Int, endColumn: Int) -> String {
        let characters = Array(line)
        let start = max(0, min(startColumn, characters.count))
        let end = max(start, min(endColumn, characters.count))
        guard start < end else { return line }

        var result = ""
        for index in characters.indices {
            let text = String(characters[index])
            if index >= start && index < end {
                result += "\u{001B}[7m\(text)\u{001B}[0m"
            } else {
                result += text
            }
        }
        return result
    }

    private static func slice(_ line: String, startColumn: Int, endColumn: Int) -> String {
        let characters = Array(line)
        let start = max(0, min(startColumn, characters.count))
        let end = max(start, min(endColumn, characters.count))
        return String(characters[start..<end])
    }

    private static func ansiEscapeEnd(in line: String, from start: String.Index) -> String.Index {
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
}

private extension String {
    func trimmedRenderPadding() -> String {
        var value = self
        while value.last == " " {
            value.removeLast()
        }
        return value
    }
}
