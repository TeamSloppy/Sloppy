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
    func handleControlC() {
        if controlCExitDetector.shouldExit() {
            Task { @MainActor in
                await self.stopTUI(reason: "TUI Ctrl+C")
            }
            return
        }

        showSystemNotice("Press Ctrl+C again to exit. Active agent run will be interrupted.", autoDismissAfter: 4)
    }

    func handleMouseInput(_ input: TerminalInput) -> Bool {
        guard case let .mouse(event) = input else { return false }

        let cell = SloppyTUIScreenCell(row: event.row, column: event.column)
        switch event.phase {
        case .scroll:
            return handleMouseWheel(event, at: cell)
        case .move:
            updateMouseHover(at: cell)
            return true
        case .press:
            guard event.button == .left else { return false }
            updateMouseHover(at: cell)
            mousePressCell = cell
            mousePressAction = hitRegion(at: cell)?.action
            selectionState.press(at: cell)
            requestRender()
            return true
        case .drag:
            guard event.button == .left else { return false }
            updateMouseHover(at: cell)
            selectionState.drag(to: cell)
            requestRender()
            return true
        case .release:
            guard event.button == .left else { return false }
            updateMouseHover(at: cell)
            let copiedRange = selectionState.release()
            defer {
                mousePressCell = nil
                mousePressAction = nil
                requestRender()
            }
            if let copiedRange {
                copySelectedText(in: copiedRange)
                return true
            }
            guard mousePressCell == cell,
                  let action = mousePressAction,
                  hitRegion(at: cell)?.action == action else {
                return true
            }
            performHitAction(action)
            return true
        }
    }

    func handleMouseWheel(_ event: TerminalMouseEvent, at cell: SloppyTUIScreenCell) -> Bool {
        let delta: Int
        switch event.button {
        case .wheelUp:
            delta = -3
        case .wheelDown:
            delta = 3
        default:
            return false
        }
        let target = scrollRegion(at: cell)?.target ?? hitRegion(at: cell).flatMap { scrollTarget(for: $0.action) }
        return scrollList(target, by: delta)
    }

    func scrollList(_ target: SloppyTUIScrollTarget?, by delta: Int) -> Bool {
        guard let target else { return false }
        switch target {
        case .activePicker:
            guard var picker = activePicker, !picker.items.isEmpty else { return true }
            picker.selectedIndex = clampedListSelection(picker.selectedIndex + delta, count: picker.items.count)
            activePicker = picker
            requestRender()
            return true
        case .commandPalette:
            let commands = commandPaletteSuggestions()
            guard !commands.isEmpty else { return true }
            commandPaletteSelection = clampedListSelection(commandPaletteSelection + delta, count: commands.count)
            requestRender()
            return true
        case .projectFile:
            guard let picker = projectFileSearchPicker(), !picker.items.isEmpty else { return true }
            projectFileSearchSelection = clampedListSelection(projectFileSearchSelection + delta, count: picker.items.count)
            requestRender()
            return true
        case .projectTask:
            guard let picker = projectTaskSearchPicker(), !picker.items.isEmpty else { return true }
            projectTaskSearchSelection = clampedListSelection(projectTaskSearchSelection + delta, count: picker.items.count)
            requestRender()
            return true
        case .sessionList:
            guard !sessionListEntries.isEmpty else { return true }
            sessionListSelectedIndex = clampedListSelection(sessionListSelectedIndex + delta, count: sessionListEntries.count)
            requestRender()
            return true
        }
    }

    func scrollTarget(for action: SloppyTUIHitAction) -> SloppyTUIScrollTarget? {
        switch action {
        case .activePicker:
            return .activePicker
        case .commandPalette:
            return .commandPalette
        case .projectFile:
            return .projectFile
        case .projectTask:
            return .projectTask
        case .sessionList:
            return .sessionList
        case .reasoningEffort, .scrollbackMode, .toggleTranscript, .openSubSession:
            return nil
        }
    }

    func clampedListSelection(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(count - 1, index))
    }

    func updateMouseHover(at cell: SloppyTUIScreenCell) {
        let previousRegion = mouseHoverRegion
        mouseHoverCell = cell
        mouseHoverRegion = hitRegion(at: cell)
        mouseHoverAction = mouseHoverRegion?.action
        if mouseHoverRegion != previousRegion {
            requestRender()
        }
    }

    func hitRegion(at cell: SloppyTUIScreenCell) -> SloppyTUIHitRegion? {
        hitRegions.last { $0.contains(cell) }
    }

    func scrollRegion(at cell: SloppyTUIScreenCell) -> SloppyTUIScrollRegion? {
        scrollRegions.last { $0.contains(cell) }
    }

    func copySelectedText(in range: SloppyTUITextSelectionRange) {
        let text = SloppyTUISelectionRenderer.selectedText(lines: lastRenderedSelectionLines, range: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        if SloppyTUIClipboard.copy(text) {
            showSystemNotice("Copied selection to clipboard.")
        } else {
            showSystemNotice("Clipboard copy is not available on this platform.")
        }
    }

    func performHitAction(_ action: SloppyTUIHitAction) {
        switch action {
        case .activePicker(let index):
            guard var picker = activePicker, picker.items.indices.contains(index) else { return }
            picker.selectedIndex = index
            let item = picker.items[index]
            activePicker = nil
            requestRender()
            Task { @MainActor in
                await self.applyPickerItem(item, kind: picker.kind)
            }
        case .commandPalette(let index):
            let commands = commandPaletteSuggestions()
            guard commands.indices.contains(index) else { return }
            applyCommandPaletteSelection(commands[index])
        case .projectFile(let index):
            guard let picker = projectFileSearchPicker(), picker.items.indices.contains(index) else { return }
            projectFileSearchSelection = index
            applyProjectFileSearchItem(picker.items[index])
        case .projectTask(let index):
            guard let picker = projectTaskSearchPicker(), picker.items.indices.contains(index) else { return }
            projectTaskSearchSelection = index
            applyProjectTaskSearchItem(picker.items[index])
        case .reasoningEffort(let index):
            effortSliderSelectionIndex = index
            applyReasoningEffortSelection()
        case .scrollbackMode(let index):
            scrollbackModeSelectionIndex = index
            applyScrollbackModeSelection()
        case .sessionList(let index):
            sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(index, entryCount: sessionListEntries.count)
            openSelectedSessionFromList(reply: false)
        case .toggleTranscript:
            transcriptExpanded.toggle()
            refreshStaticChrome()
            renderTimeline()
        case .openSubSession(let sessionID):
            Task { @MainActor in
                await self.switchSession(sessionID)
            }
        }
    }

    func handleQueuedMessageCancel(_ input: TerminalInput) -> Bool {
        guard case .key(.character("b"), let modifiers) = input,
              modifiers.contains(.control)
        else {
            return false
        }

        guard let canceled = queuedMessages.cancelNext() else {
            showSystemNotice("No queued message to cancel.")
            return true
        }

        showSystemNotice("Canceled queued message: \(canceled.displayText)")
        renderTimeline()
        return true
    }

    func handleRunInterrupt(_ input: TerminalInput) -> Bool {
        guard isPosting, !isInterruptingRun else {
            return false
        }
        guard case .key(.escape, let modifiers) = input, modifiers.isEmpty else {
            return false
        }

        Task { @MainActor in
            await self.interruptCurrentRun(
                reason: "TUI Esc",
                successMessage: "Interrupt requested.",
                failurePrefix: "Interrupt failed",
                useNotice: true
            )
        }
        return true
    }

    func renderBaseScreen(width: Int, height: Int) -> [String] {
        let footer = SloppyTUITheme.appFooter(
            width: width,
            cwd: runtime.cwd,
            mcpSummary: mcpStatusSummary,
            sourceControl: projectSourceControlFooterStatus
        )
        var preInputLines: [String] = []
        if isPosting {
            preInputLines.append(SloppyTUITheme.interruptControlLine(
                width: width,
                frame: thinkingFrame,
                isInterrupting: isInterruptingRun
            ))
        }
        let operationStatuses = orderedOperationStatuses()
        let operationStatusLine = operationStatuses.isEmpty ? nil : SloppyTUITheme.operationStatusFooterLine(
            width: width,
            statuses: operationStatuses,
            frame: thinkingFrame
        )
        let inputLines: [String]
        let editorLines = editor.render(width: width)
        if sessionListMode != .hidden, editor.getText().isEmpty {
            inputLines = SloppyTUITheme.sessionListComposerPlaceholderLines(editorLines, width: width)
        } else {
            inputLines = SloppyTUITheme.highlightedComposerLines(editorLines, shellMode: shellModeEnabled)
        }
        var metaLines: [String] = []
        if shellModeEnabled {
            metaLines.append(SloppyTUITheme.composerShellMetaLine(
                width: width,
                cwd: runtime.cwd,
                agent: agent.displayName,
                provider: providerLabel(from: selectedModel)
            ))
        } else {
            let timing = composerContextTiming()
            metaLines.append(SloppyTUITheme.composerMetaLine(
                width: width,
                mode: chatMode,
                model: selectedModel,
                agent: agent.displayName,
                provider: providerLabel(from: selectedModel),
                tokenUsage: tokenUsageSummary,
                lastTurnTokenUsage: lastTurnTokenUsage,
                runElapsed: timing.runElapsed,
                stageElapsed: timing.stageElapsed,
                animationFrame: thinkingFrame
            ))
        }
        var composer = SloppyTUIComposerLayout.lines(
            preInputLines: preInputLines,
            operationStatusLine: operationStatusLine,
            inputLines: inputLines,
            metaLines: metaLines,
            footerLine: footer
        )

        if let picker = activePicker {
            composer.insert(contentsOf: SloppyTUITheme.pickerLines(width: width, picker: picker, maxVisible: 9), at: 0)
        } else if let addDirectoryInput {
            composer.insert(contentsOf: SloppyTUITheme.addDirectoryInputLines(
                width: width,
                value: addDirectoryInput
            ), at: 0)
        } else if reasoningEffortSelectorVisible {
            composer.insert(contentsOf: SloppyTUITheme.reasoningEffortSliderLines(
                width: width,
                efforts: SloppyTUIReasoningEffortSelector.options,
                selectedIndex: currentEffortSliderIndex
            ), at: 0)
        } else if scrollbackModeSelectorVisible {
            composer.insert(contentsOf: SloppyTUITheme.scrollbackModeSliderLines(
                width: width,
                modes: SloppyTUIScrollbackModeSelector.options,
                selectedIndex: currentScrollbackModeSliderIndex,
                lineLimit: state.scrollbackLineLimit
            ), at: 0)
        } else if let palette = commandPaletteLines(width: width) {
            composer.insert(contentsOf: palette, at: 0)
        } else if let picker = projectTaskSearchPicker() {
            composer.insert(contentsOf: SloppyTUITheme.pickerLines(width: width, picker: picker, maxVisible: 9), at: 0)
        } else if let picker = projectFileSearchPicker() {
            composer.insert(contentsOf: SloppyTUITheme.pickerLines(width: width, picker: picker, maxVisible: 9), at: 0)
        }

        let bodyHeight = max(1, height - composer.count)
        let body = renderBody(width: width, height: bodyHeight)
        registerBodyHitRegions(width: width, height: bodyHeight)
        registerComposerHitRegions(startRow: bodyHeight, width: width)
        return body + composer
    }

    func registerBodyHitRegions(width: Int, height: Int) {
        guard sessionListMode != .hidden else { return }
        let listWidth: Int
        switch sessionListMode {
        case .hidden:
            return
        case .full:
            listWidth = width
        case .side:
            listWidth = min(max(36, width / 3), min(72, max(1, width - 24)))
        }
        registerScrollRegion(
            startRow: 0,
            endRow: height,
            startColumn: 0,
            endColumn: listWidth,
            target: .sessionList
        )
        registerSessionListHitRegions(startRow: 0, startColumn: 0, width: listWidth, height: height)
    }

    func registerComposerHitRegions(startRow: Int, width: Int) {
        if let picker = activePicker {
            registerPickerScrollRegion(
                picker: picker,
                startRow: startRow,
                width: width,
                target: .activePicker
            )
            registerPickerHitRegions(
                picker: picker,
                startRow: startRow,
                width: width,
                action: { .activePicker(index: $0) }
            )
        } else if reasoningEffortSelectorVisible {
            registerSliderHitRegions(
                startRow: startRow,
                width: width,
                optionCount: SloppyTUIReasoningEffortSelector.options.count,
                labelRowOffset: 2,
                action: { .reasoningEffort(index: $0) }
            )
        } else if scrollbackModeSelectorVisible {
            registerSliderHitRegions(
                startRow: startRow,
                width: width,
                optionCount: SloppyTUIScrollbackModeSelector.options.count,
                labelRowOffset: 2,
                action: { .scrollbackMode(index: $0) }
            )
        } else if commandPaletteVisible {
            registerCommandPaletteScrollRegion(startRow: startRow, width: width)
            registerCommandPaletteHitRegions(startRow: startRow, width: width)
        } else if let picker = projectTaskSearchPicker() {
            registerPickerScrollRegion(
                picker: picker,
                startRow: startRow,
                width: width,
                target: .projectTask
            )
            registerPickerHitRegions(
                picker: picker,
                startRow: startRow,
                width: width,
                action: { .projectTask(index: $0) }
            )
        } else if let picker = projectFileSearchPicker() {
            registerPickerScrollRegion(
                picker: picker,
                startRow: startRow,
                width: width,
                target: .projectFile
            )
            registerPickerHitRegions(
                picker: picker,
                startRow: startRow,
                width: width,
                action: { .projectFile(index: $0) }
            )
        }
    }

    func registerCommandPaletteScrollRegion(startRow: Int, width: Int) {
        let commands = commandPaletteSuggestions()
        guard !commands.isEmpty else { return }
        let paletteWidth = max(1, min(max(1, width - 4), 96))
        let left = max(0, (width - paletteWidth) / 2)
        let visibleCount = max(1, min(9, commands.count))
        let rowCount = visibleCount + (commands.count > visibleCount ? 1 : 0)
        registerScrollRegion(
            startRow: startRow,
            endRow: startRow + rowCount,
            startColumn: left,
            endColumn: left + paletteWidth,
            target: .commandPalette
        )
    }

    func registerPickerScrollRegion(
        picker: SloppyTUIPicker,
        startRow: Int,
        width: Int,
        target: SloppyTUIScrollTarget
    ) {
        let layout = SloppyTUITheme.pickerLayout(width: width, picker: picker, maxVisible: 9)
        let paletteWidth = layout.paletteWidth
        let left = layout.left
        let visibleCount = max(1, min(9, picker.items.count))
        var rowCount = 1
        if picker.supportsSearch {
            rowCount += 1
        }
        rowCount += picker.supportsSearch
            ? 18
            : visiblePickerRowCount(picker: picker, visibleCount: visibleCount)
        if picker.items.count > visibleCount {
            rowCount += 1
        }
        registerScrollRegion(
            startRow: startRow,
            endRow: startRow + rowCount,
            startColumn: left,
            endColumn: left + paletteWidth,
            target: target
        )
    }

    func visiblePickerRowCount(picker: SloppyTUIPicker, visibleCount: Int) -> Int {
        guard !picker.items.isEmpty else {
            return picker.supportsSearch ? 1 : 0
        }
        let start = max(0, min(picker.selectedIndex - visibleCount / 2, picker.items.count - visibleCount))
        let end = min(picker.items.count, start + visibleCount)
        var rowCount = 0
        var lastGroup: String?
        for index in start..<end {
            let item = picker.items[index]
            if let group = item.group?.trimmingCharacters(in: .whitespacesAndNewlines),
               !group.isEmpty,
               group != lastGroup {
                rowCount += 1
                lastGroup = group
            }
            rowCount += 1
        }
        return rowCount
    }

    func registerCommandPaletteHitRegions(startRow: Int, width: Int) {
        let commands = commandPaletteSuggestions()
        guard !commands.isEmpty else { return }
        let paletteWidth = max(1, min(max(1, width - 4), 96))
        let left = max(0, (width - paletteWidth) / 2)
        let visibleCount = max(1, min(9, commands.count))
        let start = max(0, min(commandPaletteSelection - visibleCount / 2, commands.count - visibleCount))
        let end = min(commands.count, start + visibleCount)
        var row = startRow
        for index in start..<end {
            registerHitRegion(
                row: row,
                startColumn: left,
                endColumn: left + paletteWidth,
                action: .commandPalette(index: index)
            )
            row += 1
        }
    }

    func registerPickerHitRegions(
        picker: SloppyTUIPicker,
        startRow: Int,
        width: Int,
        action: (Int) -> SloppyTUIHitAction
    ) {
        let layout = SloppyTUITheme.pickerLayout(width: width, picker: picker, maxVisible: 9)
        let paletteWidth = layout.paletteWidth
        let left = layout.left
        let visibleCount = max(1, min(9, picker.items.count))
        let start = max(0, min(picker.selectedIndex - visibleCount / 2, picker.items.count - visibleCount))
        let end = min(picker.items.count, start + visibleCount)
        var row = startRow + 1
        if picker.supportsSearch {
            row += 1
        }

        var lastGroup: String?
        for index in start..<end {
            let item = picker.items[index]
            if let group = item.group?.trimmingCharacters(in: .whitespacesAndNewlines),
               !group.isEmpty,
               group != lastGroup {
                row += 1
                lastGroup = group
            }
            registerHitRegion(
                row: row,
                startColumn: left,
                endColumn: left + paletteWidth,
                action: action(index)
            )
            row += 1
        }
    }

    func registerSliderHitRegions(
        startRow: Int,
        width: Int,
        optionCount: Int,
        labelRowOffset: Int,
        action: (Int) -> SloppyTUIHitAction
    ) {
        guard optionCount > 0 else { return }
        let paletteWidth = max(1, min(max(1, width - 4), 96))
        let left = max(0, (width - paletteWidth) / 2)
        let innerWidth = max(1, paletteWidth - 4)
        let sliderWidth = max(1, min(innerWidth, max(24, optionCount * 13 - 1)))
        let sliderLeft = max(0, (paletteWidth - sliderWidth) / 2)
        let base = left + sliderLeft
        let row = startRow + labelRowOffset
        for index in 0..<optionCount {
            let startColumn = base + (index * sliderWidth / optionCount)
            let endColumn = base + ((index + 1) * sliderWidth / optionCount)
            registerHitRegion(
                row: row,
                startColumn: startColumn,
                endColumn: max(startColumn + 1, endColumn),
                action: action(index)
            )
        }
    }

    func registerSessionListHitRegions(startRow: Int, startColumn: Int, width: Int, height: Int) {
        var row = startRow + 3
        var entryIndex = 0
        for section in SloppyTUISessionListSection.allCases {
            let sectionEntries = sessionListEntries.filter { $0.section == section }
            guard !sectionEntries.isEmpty else { continue }
            row += 1
            for _ in sectionEntries {
                if row < startRow + height {
                    registerHitRegion(
                        row: row,
                        startColumn: startColumn,
                        endColumn: startColumn + width,
                        action: .sessionList(index: entryIndex)
                    )
                }
                row += 1
                entryIndex += 1
            }
            row += 1
        }
    }

    func registerTextHitRegions(lines: [String], width: Int) {
        for (row, line) in lines.enumerated() {
            let plain = SloppyTUISelectionRenderer.stripANSI(line)
            if plain.contains("(ctrl+o to expand)") || plain.contains("ctrl+o toggles") {
                registerHitRegion(row: row, startColumn: 0, endColumn: width, action: .toggleTranscript)
            }
            for card in subSessionCards {
                let id = SloppyTUITheme.shortID(card.childSessionId)
                if plain.contains("subagent"), plain.contains(id) {
                    registerHitRegion(row: row, startColumn: 0, endColumn: width, action: .openSubSession(card.childSessionId))
                }
            }
        }
    }

    func registerHitRegion(row: Int, startColumn: Int, endColumn: Int, action: SloppyTUIHitAction) {
        guard row >= 0, endColumn > startColumn else { return }
        hitRegions.append(SloppyTUIHitRegion(
            row: row,
            startColumn: max(0, startColumn),
            endColumn: max(startColumn + 1, endColumn),
            action: action
        ))
    }

    func registerScrollRegion(
        startRow: Int,
        endRow: Int,
        startColumn: Int,
        endColumn: Int,
        target: SloppyTUIScrollTarget
    ) {
        guard startRow >= 0, endRow > startRow, endColumn > startColumn else { return }
        scrollRegions.append(SloppyTUIScrollRegion(
            startRow: startRow,
            endRow: endRow,
            startColumn: max(0, startColumn),
            endColumn: max(startColumn + 1, endColumn),
            target: target
        ))
    }

    func renderBody(width: Int, height: Int) -> [String] {
        if sessionListMode == .full {
            return SloppyTUITheme.sessionListLines(
                width: width,
                height: height,
                entries: sessionListEntries,
                selectedIndex: sessionListSelectedIndex,
                projectName: project.name,
                agentName: agent.displayName
            )
        }

        if sessionListMode == .side {
            let listWidth = min(max(36, width / 3), min(72, max(1, width - 24)))
            let chatWidth = max(1, width - listWidth - 1)
            let listLines = SloppyTUITheme.sessionListLines(
                width: listWidth,
                height: height,
                entries: sessionListEntries,
                selectedIndex: sessionListSelectedIndex,
                projectName: project.name,
                agentName: agent.displayName
            )
            let chatLines = renderChatBody(width: chatWidth, height: height)
            return Self.zippedPaneLines(
                left: listLines,
                right: chatLines,
                leftWidth: listWidth,
                rightWidth: chatWidth,
                separator: "│",
                height: height
            )
        }

        return renderChatBody(width: width, height: height)
    }

    func renderChatBody(width: Int, height: Int) -> [String] {
        if shouldRenderWelcome {
            let raw = SloppyTUITheme.welcomeScreen(
                width: width,
                cwd: runtime.cwd,
                project: project.name,
                agent: agent.displayName,
                model: selectedModel,
                mode: chatMode,
                mcpSummary: mcpStatusSummary,
                tipOffset: welcomeTipCursor,
                includeFooter: false
            )
            let lines = centerWelcome(raw, height: height)
            return applyTransientNoticeOverlay(
                to: lines,
                width: width,
                preferredRow: max(0, lines.count - 1)
            )
        }

        let headerLines = header.render(width: width)
        let statusLines = status.render(width: width)
        let timelineHeight = max(1, height - headerLines.count - statusLines.count)
        let visibleTimeline = renderTimelineBlocks(width: width, height: timelineHeight)
        let bottomPadding = max(0, height - headerLines.count - visibleTimeline.count - statusLines.count)
        let lines = headerLines
            + visibleTimeline
            + Array(repeating: "", count: bottomPadding)
            + statusLines
        let noticeRow = headerLines.count + visibleTimeline.count + bottomPadding - 1
        return applyTransientNoticeOverlay(to: lines, width: width, preferredRow: noticeRow)
    }

    nonisolated static func zippedPaneLines(
        left: [String],
        right: [String],
        leftWidth: Int,
        rightWidth: Int,
        separator: String,
        height: Int
    ) -> [String] {
        let leftWidth = max(1, leftWidth)
        let rightWidth = max(1, rightWidth)
        return (0..<height).map { index in
            let leftLine = left.indices.contains(index) ? left[index] : ""
            let rightLine = right.indices.contains(index) ? right[index] : ""
            let fittedLeft = SloppyTUITheme.fittedLine(leftLine, width: leftWidth)
            let fittedRight = SloppyTUITheme.fittedLine(rightLine, width: rightWidth)
            let leftPadding = String(repeating: " ", count: max(0, leftWidth - VisibleWidth.measure(fittedLeft)))
            let rightPadding = String(repeating: " ", count: max(0, rightWidth - VisibleWidth.measure(fittedRight)))
            return fittedLeft + leftPadding + separator + fittedRight + rightPadding
        }
    }

    func centerWelcome(_ lines: [String], height: Int) -> [String] {
        let content = lines.trimmingEmptyEdges()
        guard content.count < height else {
            return Array(content.suffix(height))
        }

        let topPadding = (height - content.count) / 2
        let bottomPadding = height - content.count - topPadding
        return Array(repeating: "", count: topPadding)
            + content
            + Array(repeating: "", count: bottomPadding)
    }

    func applyTransientNoticeOverlay(to lines: [String], width: Int, preferredRow: Int) -> [String] {
        guard let transientNoticeLine, !lines.isEmpty else { return lines }
        let noticeLines = SloppyTUITheme.noticeToastLines(transientNoticeLine, width: width)
        let row = max(0, min(preferredRow, lines.count - 1))
        let startRow = max(0, min(row - noticeLines.count + 1, lines.count - noticeLines.count))
        var result = lines
        for (offset, noticeLine) in noticeLines.enumerated() where result.indices.contains(startRow + offset) {
            result[startRow + offset] = noticeLine
        }
        return result
    }

    func shouldPrioritizeComposerSubmit(over input: TerminalInput) -> Bool {
        guard sessionListMode != .hidden,
              !editor.getText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              case .key(.enter, let modifiers) = input,
              modifiers.isEmpty
        else {
            return false
        }
        return true
    }

    func handleSessionListOpenShortcut(_ input: TerminalInput) -> Bool {
        guard case .key(.arrowLeft, let modifiers) = input,
              modifiers.isEmpty,
              editor.getText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sessionListMode == .hidden else {
            return false
        }
        openSessionList(mode: .side)
        return true
    }

    func handleSessionListInput(_ input: TerminalInput) -> Bool {
        guard sessionListMode != .hidden else { return false }
        if case .paste = input { return false }
        guard case let .key(key, modifiers) = input else { return true }

        switch key {
        case .arrowLeft where modifiers.isEmpty:
            if sessionListMode == .side {
                sessionListMode = .full
            }
            requestRender()
            return true
        case .arrowUp:
            sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
                sessionListSelectedIndex - 1,
                entryCount: sessionListEntries.count
            )
            requestRender()
            return true
        case .arrowDown:
            sessionListSelectedIndex = SloppyTUISessionList.clampedSelection(
                sessionListSelectedIndex + 1,
                entryCount: sessionListEntries.count
            )
            requestRender()
            return true
        case .arrowRight where modifiers.isEmpty:
            openSelectedSessionFromList(reply: false)
            return true
        case .enter:
            if !editor.getText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                createSessionFromListInput()
            } else {
                openSelectedSessionFromList(reply: false)
            }
            return true
        case .character(" ") where modifiers.isEmpty:
            guard editor.getText().isEmpty else {
                return false
            }
            openSelectedSessionFromList(reply: true)
            return true
        case .character("x") where modifiers.contains(.control):
            hideSelectedSessionFromList()
            return true
        case .character("X") where modifiers.contains(.control):
            hideSelectedSessionFromList()
            return true
        case .character("?") where modifiers.isEmpty:
            guard editor.getText().isEmpty else {
                return false
            }
            showQuickReference()
            return true
        case .escape:
            sessionListMode = .hidden
            refreshStaticChrome()
            return true
        case .character(let character)
            where !modifiers.contains(.control)
                && !modifiers.contains(.option)
                && !character.isNewline:
            return false
        default:
            return false
        }
    }

    func handleActivePicker(input: TerminalInput) -> Bool {
        guard var picker = activePicker else { return false }
        if case let .mouse(event) = input, event.phase == .scroll {
            return false
        }
        if picker.supportsSearch, case .paste(let text) = input {
            for character in text where !character.isNewline {
                picker.appendSearchCharacter(character)
            }
            activePicker = picker
            requestRender()
            return true
        }
        guard case let .key(key, modifiers) = input else { return true }
        guard !picker.items.isEmpty || picker.supportsSearch else {
            activePicker = nil
            requestRender()
            return true
        }

        switch key {
        case .arrowUp:
            picker.selectedIndex = picker.items.isEmpty ? 0 : max(0, picker.selectedIndex - 1)
            activePicker = picker
            requestRender()
            return true
        case .arrowDown:
            picker.selectedIndex = picker.items.isEmpty ? 0 : min(picker.items.count - 1, picker.selectedIndex + 1)
            activePicker = picker
            requestRender()
            return true
        case .enter, .tab:
            guard picker.items.indices.contains(picker.selectedIndex) else {
                return true
            }
            let item = picker.items[picker.selectedIndex]
            activePicker = nil
            requestRender()
            Task { @MainActor in
                await self.applyPickerItem(item, kind: picker.kind)
            }
            return true
        case .backspace:
            if picker.supportsSearch {
                picker.removeLastSearchCharacter()
                activePicker = picker
                requestRender()
            }
            return true
        case .delete:
            if picker.supportsSearch {
                picker.clearSearchQuery()
                activePicker = picker
                requestRender()
            }
            return true
        case .character("u") where picker.supportsSearch && modifiers.contains(.control):
            picker.clearSearchQuery()
            activePicker = picker
            requestRender()
            return true
        case .character(let character)
            where picker.supportsSearch
                && !modifiers.contains(.control)
                && !modifiers.contains(.option)
                && !character.isNewline:
            picker.appendSearchCharacter(character)
            activePicker = picker
            requestRender()
            return true
        case .escape:
            if picker.kind == .planInput {
                activePicker = nil
                requestRender()
                Task { @MainActor in
                    await self.cancelPlanInputRequest()
                }
                return true
            }
            if picker.kind == .workspaceAccess {
                activePicker = nil
                denyPendingWorkspaceAccess()
                requestRender()
                return true
            }
            if picker.kind == .toolApproval {
                activePicker = nil
                requestRender()
                Task { @MainActor in
                    await self.rejectPendingToolApproval()
                }
                return true
            }
            activePicker = nil
            if exitAfterModelSelection && picker.kind == .model {
                Task { @MainActor in
                    await self.stopTUI(reason: "TUI model picker")
                }
                return true
            }
            refreshStaticChrome()
            return true
        default:
            return true
        }
    }

    func handleCommandPalette(input: TerminalInput) -> Bool {
        guard commandPaletteVisible else { return false }
        guard case let .key(key, _) = input else { return false }
        let commands = commandPaletteSuggestions()
        guard !commands.isEmpty else { return false }

        switch key {
        case .arrowUp:
            commandPaletteSelection = max(0, commandPaletteSelection - 1)
            requestRender()
            return true
        case .arrowDown:
            commandPaletteSelection = min(commands.count - 1, commandPaletteSelection + 1)
            requestRender()
            return true
        case .enter, .tab:
            applyCommandPaletteSelection(commands[commandPaletteSelection])
            return true
        case .escape:
            editor.setText("")
            commandPaletteSelection = 0
            requestRender()
            return true
        default:
            return false
        }
    }

    func handleReasoningEffortSelector(input: TerminalInput) -> Bool {
        guard reasoningEffortSelectorVisible else { return false }
        guard case let .key(key, _) = input else { return false }

        switch key {
        case .arrowLeft, .arrowDown:
            effortSliderSelectionIndex = SloppyTUIReasoningEffortSelector.movedIndex(
                from: currentEffortSliderIndex,
                delta: -1
            )
            requestRender()
            return true
        case .arrowRight, .arrowUp:
            effortSliderSelectionIndex = SloppyTUIReasoningEffortSelector.movedIndex(
                from: currentEffortSliderIndex,
                delta: 1
            )
            requestRender()
            return true
        case .enter, .tab:
            applyReasoningEffortSelection()
            return true
        case .escape:
            effortSliderSelectionIndex = nil
            editor.setText("")
            persistDraft("")
            requestRender()
            return true
        default:
            return false
        }
    }

    func handleScrollbackModeSelector(input: TerminalInput) -> Bool {
        guard scrollbackModeSelectorVisible else { return false }
        guard case let .key(key, _) = input else { return false }

        switch key {
        case .arrowLeft, .arrowDown:
            scrollbackModeSelectionIndex = SloppyTUIScrollbackModeSelector.movedIndex(
                from: currentScrollbackModeSliderIndex,
                delta: -1
            )
            requestRender()
            return true
        case .arrowRight, .arrowUp:
            scrollbackModeSelectionIndex = SloppyTUIScrollbackModeSelector.movedIndex(
                from: currentScrollbackModeSliderIndex,
                delta: 1
            )
            requestRender()
            return true
        case .enter, .tab:
            applyScrollbackModeSelection()
            return true
        case .escape:
            scrollbackModeSelectionIndex = nil
            editor.setText("")
            persistDraft("")
            requestRender()
            return true
        default:
            return false
        }
    }

    func handleAddDirectoryInput(input: TerminalInput) -> Bool {
        guard addDirectoryInput != nil else { return false }

        if case .paste(let text) = input {
            addDirectoryInput = (addDirectoryInput ?? "") + text.filter { !$0.isNewline }
            requestRender()
            return true
        }

        guard case let .key(key, modifiers) = input else { return true }
        switch key {
        case .enter:
            let path = (addDirectoryInput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                requestRender()
                return true
            }
            addDirectoryInput = nil
            editor.setText("")
            persistDraft("")
            requestRender()
            Task { @MainActor in
                await self.addDirectoryPath(path)
            }
            return true
        case .tab:
            completeAddDirectoryInput()
            return true
        case .backspace:
            if addDirectoryInput?.isEmpty == false {
                addDirectoryInput?.removeLast()
                requestRender()
            }
            return true
        case .delete:
            addDirectoryInput = ""
            requestRender()
            return true
        case .character("u") where modifiers.contains(.control):
            addDirectoryInput = ""
            requestRender()
            return true
        case .character(let character)
            where !modifiers.contains(.control)
                && !modifiers.contains(.option)
                && !character.isNewline:
            addDirectoryInput = (addDirectoryInput ?? "") + String(character)
            requestRender()
            return true
        case .escape:
            addDirectoryInput = nil
            editor.setText("")
            persistDraft("")
            requestRender()
            return true
        default:
            return true
        }
    }

    func handleProjectTaskSearchInput(_ input: TerminalInput) -> Bool {
        guard SloppyTUIAutocompleteFeatureFlags.projectTaskAutocompleteEnabled else {
            return false
        }
        guard case let .key(key, _) = input else { return false }
        switch key {
        case .arrowUp, .arrowDown, .enter, .tab, .escape:
            break
        default:
            return false
        }

        guard let picker = projectTaskSearchPicker() else { return false }
        switch key {
        case .arrowUp:
            projectTaskSearchSelection = max(0, projectTaskSearchSelection - 1)
            requestRender()
            return true
        case .arrowDown:
            projectTaskSearchSelection = min(picker.items.count - 1, projectTaskSearchSelection + 1)
            requestRender()
            return true
        case .enter, .tab:
            guard !picker.items[picker.selectedIndex].value.isEmpty else {
                return true
            }
            applyProjectTaskSearchItem(picker.items[picker.selectedIndex])
            return true
        case .escape:
            if let token = currentProjectTaskToken() {
                suppressedProjectTaskSearch = SloppyTUITaskReferenceSearchSuppression(token: token)
            }
            requestRender()
            return true
        default:
            return false
        }
    }

    func handleProjectFileSearchInput(_ input: TerminalInput) -> Bool {
        guard SloppyTUIAutocompleteFeatureFlags.projectPathAutocompleteEnabled else {
            return false
        }
        guard case let .key(key, _) = input else { return false }
        switch key {
        case .arrowUp, .arrowDown, .enter, .tab, .escape:
            break
        default:
            return false
        }

        guard let picker = projectFileSearchPicker() else { return false }
        switch key {
        case .arrowUp:
            projectFileSearchSelection = max(0, projectFileSearchSelection - 1)
            requestRender()
            return true
        case .arrowDown:
            projectFileSearchSelection = min(picker.items.count - 1, projectFileSearchSelection + 1)
            requestRender()
            return true
        case .enter, .tab:
            guard !picker.items[picker.selectedIndex].value.isEmpty else {
                return true
            }
            applyProjectFileSearchItem(picker.items[picker.selectedIndex])
            return true
        case .escape:
            if let token = currentProjectFileToken() {
                suppressedProjectFileSearch = SloppyTUIProjectPathSearchSuppression(token: token)
            }
            requestRender()
            return true
        default:
            return false
        }
    }

    func handleAttachmentInput(_ input: TerminalInput) -> Bool {
        switch input {
        case .paste:
            return false
        case .key(.character("v"), let modifiers) where modifiers.contains(.control):
            if isEditingSingleLineSlashCommand, pasteClipboardTextIntoEditor() {
                return true
            }
            pasteAttachmentFromClipboard()
            return true
        default:
            return false
        }
    }

    func handleShellModeToggle(_ input: TerminalInput) -> Bool {
        guard SloppyTUIShellModeToggle.shouldToggle(input: input, editorText: editor.getText()) else {
            return false
        }
        shellModeEnabled.toggle()
        refreshStaticChrome(statusLine: shellModeEnabled ? "Shell mode enabled. Press ! on an empty prompt to exit." : nil)
        return true
    }

    func handleGlobalShortcut(_ input: TerminalInput) -> Bool {
        guard let action = SloppyTUIGlobalShortcutAction.match(input: input) else {
            return false
        }

        switch action {
        case .modelPicker:
            Task { @MainActor in await self.switchModel(nil) }
        case .projectTasks:
            Task { @MainActor in await self.showTasks() }
        case .codeEditor:
            Task { @MainActor in await self.openCodeEditor([]) }
        case .undo:
            Task { @MainActor in await self.undoLastTurn() }
        case .redo:
            Task { @MainActor in await self.redoLastTurn() }
        }
        return true
    }

    var isEditingSingleLineSlashCommand: Bool {
        let text = editor.getText()
        guard !text.contains("\n") else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    func pasteClipboardTextIntoEditor() -> Bool {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            editor.handle(input: .paste(urls.map(\.path).joined(separator: "\n")))
            return true
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            editor.handle(input: .paste(text))
            return true
        }
        #endif
        return false
    }

    func handleModeCycle(_ input: TerminalInput) -> Bool {
        guard case .key(.tab, let modifiers) = input, modifiers.isEmpty else {
            return false
        }
        chatMode = chatMode.next
        startAutoModeAnimationIfNeeded()
        refreshStaticChrome()
        return true
    }

    func handleTranscriptInput(_ input: TerminalInput) -> Bool {
        guard case let .key(key, modifiers) = input else {
            return false
        }

        switch key {
        case .character("o") where modifiers.contains(.control):
            transcriptExpanded.toggle()
            refreshStaticChrome()
            renderTimeline()
            return true
        case .character("O") where modifiers.contains(.control):
            transcriptExpanded.toggle()
            refreshStaticChrome()
            renderTimeline()
            return true
        case .character("p") where modifiers.contains(.control):
            Task { @MainActor in await self.openParentSession() }
            return true
        case .character("P") where modifiers.contains(.control):
            Task { @MainActor in await self.openParentSession() }
            return true
        case .character("g") where modifiers.contains(.control):
            Task { @MainActor in await self.openLatestSubSession() }
            return true
        case .character("G") where modifiers.contains(.control):
            Task { @MainActor in await self.openLatestSubSession() }
            return true
        case .arrowRight where modifiers.contains(.control):
            Task { @MainActor in await self.openLatestSubSession() }
            return true
        default:
            return false
        }
    }

    func handleTimelineScroll(_ input: TerminalInput) -> Bool {
        guard usesViewportTimelineScroll else {
            return false
        }
        if case let .mouse(event) = input {
            guard event.phase == .scroll else {
                return false
            }
            switch event.button {
            case .wheelUp:
                scrollTimeline(by: 3)
                return true
            case .wheelDown:
                scrollTimeline(by: -3)
                return true
            default:
                return false
            }
        }
        guard case let .key(key, modifiers) = input else {
            return false
        }

        let page = max(1, lastTimelineViewportHeight - 2)
        switch key {
        case .function(5):
            scrollTimeline(by: page)
        case .function(6):
            scrollTimeline(by: -page)
        case .home where modifiers.contains(.option) || modifiers.contains(.control):
            scrollTimelineToTop()
        case .end where modifiers.contains(.option) || modifiers.contains(.control):
            scrollTimelineToBottom()
        default:
            return false
        }
        return true
    }

    func scrollTimeline(by delta: Int) {
        timelineScrollOffset = max(0, timelineScrollOffset + delta)
        requestRender()
    }

    func scrollTimelineToTop() {
        timelineScrollOffset = Int.max
        requestRender()
    }

    func scrollTimelineToBottom() {
        timelineScrollOffset = 0
        requestRender()
    }
}
