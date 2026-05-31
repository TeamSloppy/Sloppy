import Foundation
#if canImport(AppKit)
import AppKit
#endif
import ChannelPluginSupport
import Logging
import Protocols
import TauTUI

@MainActor
extension SloppyTUIScreen {
    var usesViewportTimelineScroll: Bool {
        usesViewportTimelineScroll(width: terminal?.columns ?? 80)
    }

    func usesViewportTimelineScroll(width: Int) -> Bool {
        switch state.scrollbackMode {
        case .viewport, .limited, .full:
            return true
        case .auto:
            let totalLineCount = currentTimelineLineCount(width: width)
            return resolvedTimelineScrollBehavior(totalLineCount: totalLineCount).usesViewport
        }
    }

    var commandPaletteVisible: Bool {
        let value = editor.getText()
        guard value.hasPrefix("/") || (value.hasPrefix("@") && !skillSlashCommands.isEmpty) else { return false }
        guard !value.contains(" ") else { return false }
        return !value.contains("\n")
    }

    var reasoningEffortSelectorVisible: Bool {
        Self.isReasoningEffortSelectorText(editor.getText())
    }

    var scrollbackModeSelectorVisible: Bool {
        Self.isScrollbackModeSelectorText(editor.getText())
    }

    var currentEffortSliderIndex: Int {
        effortSliderSelectionIndex ?? SloppyTUIReasoningEffortSelector.index(for: reasoningEffort)
    }

    var currentScrollbackModeSliderIndex: Int {
        scrollbackModeSelectionIndex ?? SloppyTUIScrollbackModeSelector.index(for: state.scrollbackMode)
    }

    static func isReasoningEffortSelectorText(_ value: String) -> Bool {
        guard !value.contains("\n") else { return false }
        let lowercased = value.lowercased()
        return lowercased.trimmingCharacters(in: .whitespaces) == "/effort"
    }

    static func isScrollbackModeSelectorText(_ value: String) -> Bool {
        guard !value.contains("\n") else { return false }
        let lowercased = value.lowercased()
        return lowercased.trimmingCharacters(in: .whitespaces) == "/scrollback"
    }

    var allSlashCommands: [SloppyTUISlashCommand] {
        Self.baseSlashCommands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var allHelpCommands: [SloppyTUISlashCommand] {
        (Self.baseSlashCommands + skillSlashCommands).sorted {
            let lhs = $0.invocationPrefix + $0.name
            let rhs = $1.invocationPrefix + $1.name
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var commandPaletteCommands: [SloppyTUISlashCommand] {
        if editor.getText().hasPrefix("@") {
            return skillSlashCommands.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return allSlashCommands
    }

    func commandPaletteSuggestions() -> [SloppyTUISlashCommand] {
        let prefix = String(editor.getText().dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let commands = commandPaletteCommands
        let matches: [SloppyTUISlashCommand]
        if prefix.isEmpty {
            matches = commands
        } else {
            matches = commands.filter { command in
                command.name.lowercased().hasPrefix(prefix)
            }
        }
        if commandPaletteSelection >= matches.count {
            commandPaletteSelection = max(0, matches.count - 1)
        }
        return matches
    }

    func commandPaletteLines(width: Int) -> [String]? {
        guard commandPaletteVisible else { return nil }
        let suggestions = commandPaletteSuggestions()
        guard !suggestions.isEmpty else { return nil }
        return SloppyTUITheme.commandPaletteLines(
            width: width,
            commands: suggestions,
            selectedIndex: commandPaletteSelection,
            maxVisible: 9
        )
    }

    func projectTaskSearchPicker() -> SloppyTUIPicker? {
        guard SloppyTUIAutocompleteFeatureFlags.projectTaskAutocompleteEnabled else {
            return nil
        }
        guard let token = currentProjectTaskToken() else {
            return nil
        }
        guard suppressedProjectTaskSearch?.matches(token) != true else {
            return nil
        }

        let query = token.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeTasks = project.tasks.filter { task in
            !task.isArchived && ProjectTaskStatus(rawValue: task.status)?.isTerminal != true
        }
        if activeTasks.isEmpty {
            if projectTaskAutocompleteLoading {
                return SloppyTUIPicker(
                    kind: .projectTask,
                    title: "Loading project tasks",
                    items: [
                        SloppyTUIPickerItem(
                            value: "",
                            label: "Collecting tasks...",
                            description: "Task suggestions will appear in a moment.",
                            isCurrent: false
                        ),
                    ],
                    selectedIndex: 0
                )
            }
            reloadProjectForTaskAutocompleteIfNeeded()
            return nil
        }

        let items: [SloppyTUIPickerItem]
        if let cached = projectTaskSearchCache,
           cached.generation == projectTaskGeneration,
           cached.token == token.rawToken {
            items = cached.items
        } else {
            let matches = matchingProjectTasks(activeTasks, query: query, limit: 30)
            guard !matches.isEmpty else {
                return nil
            }
            items = matches.map(projectTaskPickerItem)
            projectTaskSearchCache = (projectTaskGeneration, token.rawToken, items)
        }

        if projectTaskSearchSelection >= items.count {
            projectTaskSearchSelection = max(0, items.count - 1)
        }
        return SloppyTUIPicker(
            kind: .projectTask,
            title: "Reference project task",
            items: items,
            selectedIndex: projectTaskSearchSelection
        )
    }

    func matchingProjectTasks(_ tasks: [ProjectTask], query: String, limit: Int) -> [ProjectTask] {
        let tokens = query
            .split { character in
                character.isWhitespace || character == "-" || character == "_" || character == "/"
            }
            .map(String.init)
        let ordered = tasks.sorted { lhs, rhs in
            let lhsRank = projectTaskStatusRank(lhs.status)
            let rhsRank = projectTaskStatusRank(rhs.status)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        guard !tokens.isEmpty else {
            return Array(ordered.prefix(limit))
        }
        return Array(ordered.filter { task in
            let haystack = [
                task.id,
                task.title,
                task.status,
                task.priority,
                task.kind?.rawValue ?? "",
            ].joined(separator: " ")
            return tokens.allSatisfy { token in
                haystack.localizedCaseInsensitiveContains(token)
            }
        }.prefix(limit))
    }

    func projectTaskStatusRank(_ status: String) -> Int {
        switch ProjectTaskStatus(rawValue: status) {
        case .ready:
            return 0
        case .backlog:
            return 1
        case .inProgress:
            return 2
        case .waitingInput:
            return 3
        case .needsReview:
            return 4
        case .pendingApproval:
            return 5
        case .blocked:
            return 6
        case .done:
            return 7
        case .cancelled:
            return 8
        case nil:
            return 9
        }
    }

    func projectTaskPickerItem(_ task: ProjectTask) -> SloppyTUIPickerItem {
        SloppyTUIPickerItem(
            value: task.id,
            label: "#\(task.id)",
            description: "[\(task.status)] \(task.title)",
            isCurrent: false,
            group: task.priority
        )
    }

    func applyProjectTaskSearchItem(_ item: SloppyTUIPickerItem) {
        guard let token = currentProjectTaskToken() else {
            return
        }

        var lines = editor.getText().components(separatedBy: "\n")
        guard lines.indices.contains(token.line) else {
            return
        }

        var line = lines[token.line]
        let start = line.index(line.startIndex, offsetBy: token.startColumn)
        let end = line.index(line.startIndex, offsetBy: token.endColumn)
        let insertedToken = "#\(item.value)"
        let suppression = SloppyTUITaskReferenceSearchSuppression(
            rawToken: insertedToken,
            line: token.line,
            startColumn: token.startColumn
        )
        line.replaceSubrange(start..<end, with: insertedToken + " ")
        lines[token.line] = line
        projectTaskSearchSelection = 0
        editor.setText(lines.joined(separator: "\n"))
        suppressedProjectTaskSearch = suppression
        requestRender()
    }

    func currentProjectTaskToken() -> SloppyTUITaskReferenceTokens.Token? {
        let cursor = editor.getCursor()
        if let cache = currentProjectTaskTokenCache,
           cache.revision == editorTextRevision,
           cache.line == cursor.line,
           cache.column == cursor.col {
            return cache.token
        }
        let text = editor.getText()
        let lines = text.components(separatedBy: "\n")
        let token = SloppyTUITaskReferenceTokens.tokenBeforeCursor(
            lines: lines,
            cursorLine: cursor.line,
            cursorColumn: cursor.col
        )
        currentProjectTaskTokenCache = (editorTextRevision, cursor.line, cursor.col, token)
        return token
    }

    func projectFileSearchPicker() -> SloppyTUIPicker? {
        guard SloppyTUIAutocompleteFeatureFlags.projectPathAutocompleteEnabled else {
            return nil
        }
        guard let token = currentProjectFileToken() else {
            return nil
        }
        guard suppressedProjectFileSearch?.matches(token) != true else {
            return nil
        }

        let query = token.path
        guard shouldSearchProjectFiles(query: query) else {
            return nil
        }
        guard let index = projectFileIndex else {
            guard projectFileIndexLoading else {
                return nil
            }
            return SloppyTUIPicker(
                kind: .projectFile,
                title: "Indexing project files",
                items: [
                    SloppyTUIPickerItem(
                        value: "",
                        label: "Collecting files...",
                        description: "Path suggestions will appear in a moment.",
                        isCurrent: false
                    ),
                ],
                selectedIndex: 0
            )
        }
        let lookup = projectFileIndexLookup ?? index.makeLookup()
        guard !lookup.containsFile(query) else {
            return nil
        }
        guard !(query.hasSuffix("/") && lookup.containsDirectory(query)) else {
            return nil
        }

        let items: [SloppyTUIPickerItem]
        if let cached = projectFileSearchCache,
           cached.generation == projectFileIndexGeneration,
           cached.token == token.rawToken {
            items = cached.items
        } else {
            let entries = lookup.completionSearch(query, limit: 30, fallbackSearch: index.search)
            guard !entries.isEmpty else {
                return nil
            }
            items = entries.map(projectFilePickerItem)
            projectFileSearchCache = (projectFileIndexGeneration, token.rawToken, items)
        }

        if projectFileSearchSelection >= items.count {
            projectFileSearchSelection = max(0, items.count - 1)
        }
        return SloppyTUIPicker(
            kind: .projectFile,
            title: "Attach project path",
            items: items,
            selectedIndex: projectFileSearchSelection
        )
    }

    func shouldSearchProjectFiles(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.hasSuffix("/") {
            return true
        }
        return trimmed.count >= 2
    }

    func projectFilePickerItem(entry: ProjectFileIndexEntry) -> SloppyTUIPickerItem {
        let value = entry.type == .directory ? entry.path + "/" : entry.path
        let displayPath = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = (displayPath as NSString).lastPathComponent + (entry.type == .directory ? "/" : "")
        let parent = (displayPath as NSString).deletingLastPathComponent
        return SloppyTUIPickerItem(
            value: value,
            label: name,
            description: parent == "." ? "" : parent,
            isCurrent: false
        )
    }

    func applyProjectFileSearchItem(_ item: SloppyTUIPickerItem) {
        guard let token = currentProjectFileToken() else {
            return
        }

        var lines = editor.getText().components(separatedBy: "\n")
        guard lines.indices.contains(token.line) else {
            return
        }

        var line = lines[token.line]
        let start = line.index(line.startIndex, offsetBy: token.startColumn)
        let end = line.index(line.startIndex, offsetBy: token.endColumn)
        let insertedToken = "@\(SloppyTUIProjectPathTokens.escapedTokenValue(item.value))"
        let suppression = SloppyTUIProjectPathSearchSuppression(
            rawToken: insertedToken,
            line: token.line,
            startColumn: token.startColumn
        )
        line.replaceSubrange(start..<end, with: insertedToken + " ")
        lines[token.line] = line
        editor.handle(input: .key(.escape))
        projectFileSearchSelection = 0
        editor.setText(lines.joined(separator: "\n"))
        suppressedProjectFileSearch = suppression
        requestRender()
    }

    func currentProjectFileToken() -> SloppyTUIProjectPathTokens.Token? {
        let cursor = editor.getCursor()
        if let cache = currentProjectFileTokenCache,
           cache.revision == editorTextRevision,
           cache.line == cursor.line,
           cache.column == cursor.col {
            return cache.token
        }
        let text = editor.getText()
        let lines = text.components(separatedBy: "\n")
        let token = SloppyTUIProjectPathTokens.tokenBeforeCursor(
            lines: lines,
            cursorLine: cursor.line,
            cursorColumn: cursor.col
        )
        currentProjectFileTokenCache = (editorTextRevision, cursor.line, cursor.col, token)
        return token
    }

    func applyCommandPaletteSelection(_ command: SloppyTUISlashCommand) {
        commandPaletteSelection = 0
        let raw = "\(command.invocationPrefix)\(command.name)"
        if command.invocationPrefix == "@" {
            editor.setText(raw + " ")
            requestRender()
            return
        }
        if command.name.lowercased() == "effort" {
            showReasoningEffortSelector()
            return
        }
        if command.name.lowercased() == "scrollback" {
            showScrollbackModeSelector()
            return
        }
        if command.name.lowercased() == "add_dir" || command.name.lowercased() == "add-dir" {
            showAddDirectoryInput()
            return
        }
        if command.name.lowercased() == "workspace" {
            editor.setText("")
            persistDraft("")
            requestRender()
            Task { @MainActor in
                await self.showWorkspace()
            }
            return
        }
        if command.requiresArgument {
            editor.setText(raw + " ")
            requestRender()
            return
        }

        editor.setText("")
        persistDraft("")
        requestRender()
        Task { @MainActor in
            await self.handleCommand(raw)
        }
    }

    func showReasoningEffortSelector() {
        effortSliderSelectionIndex = SloppyTUIReasoningEffortSelector.index(for: reasoningEffort)
        editor.setText("/effort")
        requestRender()
    }

    func applyReasoningEffortSelection() {
        let effort = SloppyTUIReasoningEffortSelector.effort(at: currentEffortSliderIndex)
        reasoningEffort = effort
        effortSliderSelectionIndex = nil
        editor.setText("")
        persistDraft("")
        appendLocalCard("Reasoning effort set to `\(effort.rawValue)`.", autoDismissAfter: 6)
    }

    func showScrollbackModeSelector() {
        scrollbackModeSelectionIndex = SloppyTUIScrollbackModeSelector.index(for: state.scrollbackMode)
        editor.setText("/scrollback")
        requestRender()
    }

    func applyScrollbackModeSelection() {
        let mode = SloppyTUIScrollbackModeSelector.mode(at: currentScrollbackModeSliderIndex)
        applyScrollbackMode(mode)
        scrollbackModeSelectionIndex = nil
        editor.setText("")
        persistDraft("")
        appendLocalCard("""
        ## Scrollback
        - mode: `\(state.scrollbackMode.rawValue)`
        - line limit: `\(state.scrollbackLineLimit)`
        - behavior: \(scrollbackBehaviorDescription())
        """, autoDismissAfter: 12)
    }

    func showAddDirectoryInput() {
        addDirectoryInput = ""
        editor.setText("/add_dir")
        requestRender()
    }

    func providerLabel(from model: String) -> String {
        if let separator = model.firstIndex(of: ":") {
            return String(model[..<separator])
        }
        return "native"
    }
}
