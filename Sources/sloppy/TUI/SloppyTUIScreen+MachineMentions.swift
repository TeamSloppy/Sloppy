import Foundation
import Protocols
import TauTUI

@MainActor
extension SloppyTUIScreen {
    private var machineMentionScope: String { "\(service.uiDraftNamespace)|\(project.id)" }

    private func machineMentionToken() -> (line: Int, range: Range<String.Index>, query: String)? {
        let cursor = editor.getCursor()
        let lines = editor.getLines()
        guard lines.indices.contains(cursor.line) else { return nil }
        let line = lines[cursor.line]
        let end = line.index(line.startIndex, offsetBy: min(cursor.col, line.count))
        let start = line[..<end].lastIndex(where: \.isWhitespace).map { line.index(after: $0) } ?? line.startIndex
        guard start < end, line[start] == "$" else { return nil }
        let query = line[line.index(after: start)..<end]
        func aliasCharacter(_ character: Character) -> Bool {
            character == "_" || character == "-" || (character.isASCII && (character.isLetter || character.isNumber))
        }
        guard query.allSatisfy(aliasCharacter) else { return nil }
        let tail = line[end...].firstIndex(where: { !aliasCharacter($0) }) ?? line.endIndex
        return (cursor.line, start..<tail, String(query))
    }

    func machineMentionPicker() -> SloppyTUIPicker? {
        guard !shellModeEnabled, let token = machineMentionToken(), token.query != suppressedMachineMention else { return nil }
        let scope = machineMentionScope
        if machineMentionRequest?.scope != scope || Date().timeIntervalSince(machineMentionRequest?.started ?? .distantPast) > 20 {
            let started = Date()
            let backend = service
            let projectId = project.id
            machineMentionRequest = (scope, started)
            Task { @MainActor [weak self] in
                let items = (try? await backend.listMachineMentions(projectId: projectId)) ?? []
                guard let self, machineMentionScope == scope, machineMentionRequest?.started == started else { return }
                machineMentionCatalog = (scope, items)
                requestRender()
            }
        }
        guard let catalog = machineMentionCatalog, catalog.scope == scope else { return nil }
        let matches = catalog.items.filter {
            token.query.isEmpty || $0.alias.localizedCaseInsensitiveContains(token.query) || $0.name.localizedCaseInsensitiveContains(token.query)
        }.prefix(12)
        guard !matches.isEmpty else { return nil }
        let items = matches.map { machine in
            SloppyTUIPickerItem(value: machine.alias, label: machine.alias,
                description: "\(machine.name) · \(machine.transport == .ssh ? "SSH" : "Relay")", isCurrent: false)
        }
        machineMentionSelection = min(machineMentionSelection, items.count - 1)
        return SloppyTUIPicker(kind: .machineMention, title: "Machines", items: items, selectedIndex: machineMentionSelection)
    }

    func handleMachineMentionInput(_ input: TerminalInput) -> Bool {
        guard case let .key(key, modifiers) = input, modifiers.isEmpty, let picker = machineMentionPicker() else { return false }
        switch key {
        case .arrowUp: machineMentionSelection = max(0, machineMentionSelection - 1)
        case .arrowDown: machineMentionSelection = min(picker.items.count - 1, machineMentionSelection + 1)
        case .enter, .tab: applyMachineMention(picker.items[picker.selectedIndex])
        case .escape: suppressedMachineMention = machineMentionToken()?.query
        default: return false
        }
        requestRender()
        return true
    }

    func applyMachineMention(_ item: SloppyTUIPickerItem) {
        guard let token = machineMentionToken() else { return }
        var lines = editor.getLines()
        let line = lines[token.line]
        let followingWhitespace = token.range.upperBound < line.endIndex && line[token.range.upperBound].isWhitespace
        lines[token.line].replaceSubrange(token.range, with: item.value + (followingWhitespace ? "" : " "))
        editor.setText(lines.joined(separator: "\n"))
        requestRender()
    }
}
