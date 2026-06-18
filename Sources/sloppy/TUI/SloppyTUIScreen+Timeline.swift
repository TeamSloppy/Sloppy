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
    func invalidateSessionTimelineCache() {
        sessionTimelineRevision += 1
        sessionTimelineCache = nil
    }

    func renderTimeline() {
        if sessionCards.isEmpty,
           liveAssistantDraft == nil,
           queuedMessages.isEmpty,
           localCards.isEmpty {
            timeline.text = ""
        }
        refreshStaticChrome()
        requestRender()
    }

    func indexedAdditionalDirectoryURLs(projectRootURL: URL) -> [URL] {
        let projectRootPath = projectRootURL.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()
        let fallbackPlansPath = runtime.workspaceRoot
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(project.id, isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
            .path
        return (persistedDirectoriesForCurrentSession() + [fallbackPlansPath]).compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard url.path != projectRootPath,
                  seen.insert(url.path).inserted
            else {
                return nil
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return url
        }
    }

    func projectFileIndexRootPath(rootURL: URL, additionalRootURLs: [URL]) -> String {
        ([rootURL.resolvingSymlinksInPath().standardizedFileURL.path] + additionalRootURLs.map(\.path))
            .joined(separator: "\n")
    }

    func liveAssistantBlocks() -> [SloppyTUITimelineBlock] {
        guard let liveAssistantDraft else {
            return []
        }

        let spinner = SloppyTUITheme.waitingIndicator(
            frame: thinkingFrame,
            word: thinkingWord,
            tokenUsage: lastTurnTokenUsage
        )
        let body = liveAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return [.local(spinner)]
        }
        return [.message(role: .assistant, text: body + "\n\n" + spinner)]
    }

    func queuedMessageBlocks() -> [SloppyTUITimelineBlock] {
        queuedMessages.messages.map { .queuedMessage($0) }
    }

    func renderTimelineBlocks(width: Int, height: Int) -> [String] {
        let segments = timelineSegments(width: width)
        if segments.isEmpty {
            return timeline.render(width: width)
        }

        return visibleTimelineLines(segments, height: height)
    }

    func timelineSegments(width: Int) -> [[String]] {
        let sessionTimeline = cachedSessionTimelineLines(width: width)
        let dynamicBlocks = SloppyTUIChatTimelineComposition.blocks(
            sessionBlocks: [],
            liveAssistantBlocks: liveAssistantBlocks(),
            queuedMessageBlocks: queuedMessageBlocks(),
            workspaceDiffPreview: workspaceDiffPreview,
            localCards: localCards
        )
        let dynamicLines = renderTimelineLines(dynamicBlocks, width: width)
        let containsToolTranscriptBlock = sessionTimeline.containsToolTranscriptBlock
            || dynamicBlocks.contains(where: isToolTranscriptBlock)

        var segments: [[String]] = []
        if !sessionTimeline.lines.isEmpty {
            segments.append(sessionTimeline.lines)
        }
        if !dynamicLines.isEmpty {
            if !segments.isEmpty {
                segments.append([""])
            }
            segments.append(dynamicLines)
        }
        if transcriptExpanded || containsToolTranscriptBlock {
            if !segments.isEmpty {
                segments.append([""])
            }
            segments.append([
                SloppyTUITheme.transcriptHintLine(
                    expanded: transcriptExpanded,
                    childSessionCount: subSessionCards.count,
                    width: width
                ),
            ])
        }

        return segments
    }

    func currentTimelineLineCount(width: Int) -> Int {
        let segments = timelineSegments(width: width)
        guard !segments.isEmpty else {
            return timeline.render(width: width).count
        }
        return segments.reduce(0) { $0 + $1.count }
    }

    func cachedSessionTimelineLines(width: Int) -> (lines: [String], containsToolTranscriptBlock: Bool) {
        let animationFrameKey = shouldAnimateCachedSessionBlocks ? thinkingFrame : 0
        if let cache = sessionTimelineCache,
           cache.revision == sessionTimelineRevision,
           cache.width == width,
           cache.transcriptExpanded == transcriptExpanded,
           cache.animationFrameKey == animationFrameKey {
            return (cache.lines, cache.containsToolTranscriptBlock)
        }

        let lines = renderTimelineLines(sessionCards, width: width)
        let containsToolTranscriptBlock = sessionCards.contains(where: isToolTranscriptBlock)
        sessionTimelineCache = SloppyTUISessionTimelineCache(
            revision: sessionTimelineRevision,
            width: width,
            transcriptExpanded: transcriptExpanded,
            animationFrameKey: animationFrameKey,
            lines: lines,
            containsToolTranscriptBlock: containsToolTranscriptBlock
        )
        return (lines, containsToolTranscriptBlock)
    }

    var shouldAnimateCachedSessionBlocks: Bool {
        sessionCards.count <= SloppyTUITimelinePerformance.animatedSessionBlockLimit
            && sessionCards.contains(where: isAnimatedTimelineBlock)
    }

    func renderTimelineLines(_ blocks: [SloppyTUITimelineBlock], width: Int) -> [String] {
        guard !blocks.isEmpty else {
            return []
        }

        var lines: [String] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if !lines.isEmpty {
                lines.append("")
            }

            if !transcriptExpanded, isToolTranscriptBlock(block) {
                let endIndex = compactToolGroupEnd(startingAt: index, in: blocks)
                appendCompactToolGroup(Array(blocks[index..<endIndex]), to: &lines, width: width)
                index = endIndex
                continue
            }

            switch block {
            case .message(let role, let text):
                if role == .user {
                    lines.append(contentsOf: SloppyTUITheme.userMessageLines(text, width: width))
                } else {
                    lines.append(contentsOf: renderMarkdown(text, width: width))
                }
            case .local(let text):
                lines.append(contentsOf: renderMarkdown(text, width: width))
            case .queuedMessage(let message):
                lines.append(contentsOf: SloppyTUITheme.queuedMessageLines(message, width: width))
            case .error(let text):
                lines.append(contentsOf: renderMarkdown(SloppyTUITheme.errorBlock(text), width: width))
            case .thinking(let text):
                lines.append(contentsOf: SloppyTUITheme.thinkingLines(text, width: width))
            case .attachment(let name, let mimeType, let sizeBytes):
                lines.append(SloppyTUITheme.attachmentLine(name: name, mimeType: mimeType, sizeBytes: sizeBytes, width: width))
            case .subSession(let childSessionId, let title, let status):
                lines.append(SloppyTUITheme.subSessionLine(
                    title: title,
                    childSessionId: childSessionId,
                    status: status,
                    frame: thinkingFrame,
                    width: width
                ))
            case .memoryCheckpoint(let checkpoint):
                lines.append(SloppyTUITheme.memoryCheckpointLine(checkpoint, frame: thinkingFrame, width: width))
            case .buildProgress(let progress):
                lines.append(contentsOf: SloppyTUITheme.buildProgressLines(progress, width: width))
            case .planArtifact(let artifact):
                lines.append(contentsOf: renderMarkdown("""
                ## Plan web page
                `\(artifact.planName)`

                Run `/plan-web` to open it.
                """, width: width))
            case .inputRequest(let request):
                lines.append(contentsOf: renderMarkdown(SloppyTUIPlanInputPicker.requestText(request), width: width))
            case .workspaceDiff(let branch, let linesAdded, let linesDeleted, let diff, let truncated):
                lines.append(SloppyTUITheme.workspaceDiffHeaderLine(
                    branch: branch,
                    linesAdded: linesAdded,
                    linesDeleted: linesDeleted,
                    truncated: truncated,
                    width: width
                ))
                lines.append(contentsOf: SloppyTUITheme.diffLines(
                    clip(diff, maxCharacters: 18_000),
                    width: width
                ))
            case .toolCall(let tool, let reason, let summary, let details):
                lines.append(SloppyTUITheme.toolCallLine(tool: tool, reason: reason, summary: summary, width: width))
                if transcriptExpanded, let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append(contentsOf: renderMarkdown(details, width: width))
                }
            case .toolResult(let tool, _, let ok, let error, let durationMs, let details):
                lines.append(SloppyTUITheme.toolResultLine(tool: tool, ok: ok, error: error, durationMs: durationMs, width: width))
                if transcriptExpanded, let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append(contentsOf: renderMarkdown(details, width: width))
                }
            }
            index += 1
        }

        return lines
    }

    func isToolTranscriptBlock(_ block: SloppyTUITimelineBlock) -> Bool {
        switch block {
        case .toolCall, .toolResult:
            return true
        default:
            return false
        }
    }

    func isAnimatedTimelineBlock(_ block: SloppyTUITimelineBlock) -> Bool {
        switch block {
        case .subSession:
            return true
        case .memoryCheckpoint(let checkpoint):
            return checkpoint.status == .started
        default:
            return false
        }
    }

    func updatePendingPlanInputRequest(_ request: PlanInputRequest?) {
        let previousRequestID = pendingPlanInputRequest?.id
        let previousSelectedIndex = activePicker?.kind == .planInput ? activePicker?.selectedIndex ?? 0 : 0
        pendingPlanInputRequest = request

        guard let request else {
            if activePicker?.kind == .planInput {
                activePicker = nil
                refreshStaticChrome()
            }
            return
        }

        activePicker = SloppyTUIPlanInputState.picker(
            for: request,
            previousRequestID: previousRequestID,
            previousSelectedIndex: previousSelectedIndex
        )
        refreshStaticChrome(statusLine: "select answer with arrows, Enter to submit, Esc to cancel")
    }

    func refreshPendingToolApproval() async {
        guard hasPersistedSession else {
            updatePendingToolApproval(nil)
            return
        }
        let approvals = (try? await service.listPendingToolApprovals()) ?? []
        let approval = SloppyTUIToolApprovalState.pendingApproval(
            in: approvals,
            agentID: agent.id,
            sessionID: session.id
        )
        updatePendingToolApproval(approval)
    }

    func updatePendingToolApproval(_ approval: ToolApprovalRecord?) {
        let previousApprovalID = pendingToolApproval?.id
        let previousSelectedIndex = activePicker?.kind == .toolApproval ? activePicker?.selectedIndex ?? 0 : 0
        pendingToolApproval = approval

        guard let approval else {
            if activePicker?.kind == .toolApproval {
                activePicker = nil
                refreshStaticChrome()
            }
            dismissPendingToolApprovalPreview()
            return
        }

        guard pendingPlanInputRequest == nil else {
            return
        }
        showPendingToolApprovalPreviewIfNeeded(approval)
        activePicker = SloppyTUIToolApprovalState.picker(
            for: approval,
            previousApprovalID: previousApprovalID,
            previousSelectedIndex: previousSelectedIndex
        )
        refreshStaticChrome(statusLine: "select approval action with arrows, Enter to apply, Esc to deny")
    }

    func applyToolApprovalDecision(_ value: String) async {
        guard let approval = pendingToolApproval else {
            appendLocalCard("No pending tool approval is available.", autoDismissAfter: 8)
            return
        }
        do {
            switch value {
            case "approve_once":
                _ = try await service.approveToolApproval(
                    id: approval.id,
                    request: ToolApprovalDecisionRequest(decidedBy: "tui", scope: .once)
                )
                appendLocalCard("Approved `\(approval.tool)` once.", autoDismissAfter: 6)
            case "approve_session":
                _ = try await service.approveToolApproval(
                    id: approval.id,
                    request: ToolApprovalDecisionRequest(decidedBy: "tui", scope: .session)
                )
                appendLocalCard("Approved `\(approval.tool)` for this session.", autoDismissAfter: 6)
            case "reject":
                _ = try await service.rejectToolApproval(
                    id: approval.id,
                    request: ToolApprovalDecisionRequest(decidedBy: "tui")
                )
                appendLocalCard("Denied `\(approval.tool)`.", autoDismissAfter: 6)
            default:
                return
            }
            pendingToolApproval = nil
            dismissPendingToolApprovalPreview()
            if activePicker?.kind == .toolApproval {
                activePicker = nil
            }
            refreshStaticChrome()
            await reloadSession()
        } catch {
            pendingToolApproval = approval
            activePicker = SloppyTUIToolApprovalState.picker(for: approval, previousApprovalID: approval.id, previousSelectedIndex: 0)
            appendLocalCard("Tool approval decision failed: \(String(describing: error))", autoDismissAfter: 10)
        }
    }

    func showPendingToolApprovalPreviewIfNeeded(_ approval: ToolApprovalRecord) {
        guard pendingToolApprovalPreviewCard?.approvalID != approval.id else {
            return
        }
        dismissPendingToolApprovalPreview()
        guard let display = SloppyTUITimelineDisplay.toolApprovalDisplay(approval) else {
            return
        }
        let cardID = appendLocalCardReturningID(display)
        pendingToolApprovalPreviewCard = (approvalID: approval.id, cardID: cardID)
    }

    func dismissPendingToolApprovalPreview() {
        guard let preview = pendingToolApprovalPreviewCard else {
            return
        }
        dismissLocalCards { card in
            card.id == preview.cardID
        }
        pendingToolApprovalPreviewCard = nil
    }

    func rejectPendingToolApproval() async {
        await applyToolApprovalDecision("reject")
    }

    func answerPlanInput(with item: SloppyTUIPickerItem) async {
        guard let request = pendingPlanInputRequest,
              let payload = SloppyTUIPlanInputPicker.answerRequest(for: item, request: request)
        else {
            appendLocalCard("Could not read the pending input request.", autoDismissAfter: 8)
            return
        }
        await submitPlanInput(request: request, payload: payload, busyLabel: "Submitting input answer...")
    }

    func cancelPlanInputRequest() async {
        guard let request = pendingPlanInputRequest else {
            return
        }
        let payload = PlanInputAnswerRequest(status: .cancelled, answers: [], userId: "tui")
        await submitPlanInput(request: request, payload: payload, busyLabel: "Cancelling input request...")
    }

    func submitPlanInput(
        request: PlanInputRequest,
        payload: PlanInputAnswerRequest,
        busyLabel: String
    ) async {
        guard !isPosting else {
            appendLocalCard("A message is already in flight. Use `/stop` if you need to interrupt it.")
            return
        }

        isPosting = true
        taskStartedAt = Date()
        lastTaskElapsed = nil
        liveRunStage = nil
        liveRunStatusLine = busyLabel
        startThinkingAnimation()
        refreshStaticChrome(statusLine: busyLabel)
        let undoBaseline = await makeUndoBaseline()
        do {
            _ = try await service.answerAgentPlanInput(
                agentID: agent.id,
                sessionID: session.id,
                requestID: request.id,
                payload: payload
            )
            pendingPlanInputRequest = nil
            activePicker = nil
            recordUndoPointIfNeeded(undoBaseline)
            liveRunStatusLine = "Refreshing session..."
            refreshStaticChrome()
            await Task.yield()
            await reloadSession()
            await refreshTokenUsage(includeCost: true)
            petMood = payload.status == .answered ? .happy : petMood
        } catch {
            petMood = .sad
            pendingPlanInputRequest = request
            activePicker = SloppyTUIPlanInputPicker.picker(for: request)
            appendLocalCard("Input answer failed: \(String(describing: error))")
        }
        if let taskStartedAt {
            let elapsed = Date().timeIntervalSince(taskStartedAt)
            lastTaskElapsed = elapsed
            cumulativeAgentActiveTime += elapsed
        }
        taskStartedAt = nil
        isPosting = false
        stopThinkingAnimation()
        liveRunStatusLine = nil
        refreshStaticChrome()
        renderTimeline()
    }

    func compactToolGroupEnd(startingAt startIndex: Int, in blocks: [SloppyTUITimelineBlock]) -> Int {
        var index = startIndex
        while index < blocks.count, isToolTranscriptBlock(blocks[index]) {
            index += 1
        }
        return index
    }

    func appendCompactToolGroup(_ blocks: [SloppyTUITimelineBlock], to lines: inout [String], width: Int) {
        let visibleBlocks = SloppyTUIToolTranscriptCompactor.visibleExecutingBlocks(in: blocks)
        lines.append(SloppyTUITheme.toolPaddingLine(width: width))
        for block in visibleBlocks {
            switch block {
            case .toolCall(let tool, let reason, let summary, _):
                lines.append(SloppyTUITheme.toolCallLine(tool: tool, reason: reason, summary: summary, width: width))
            case .toolResult(let tool, _, let ok, let error, let durationMs, _):
                lines.append(SloppyTUITheme.toolResultLine(tool: tool, ok: ok, error: error, durationMs: durationMs, width: width))
            default:
                break
            }
        }
        let hiddenCount = blocks.count - visibleBlocks.count
        if hiddenCount > 0 {
            lines.append(SloppyTUITheme.toolOverflowLine(hiddenCount: hiddenCount, width: width))
        }
        lines.append(SloppyTUITheme.toolPaddingLine(width: width))
    }

    func visibleTimelineLines(_ segments: [[String]], height: Int) -> [String] {
        lastTimelineViewportHeight = max(1, height)
        let lineCount = segments.reduce(0) { $0 + $1.count }
        let behavior = resolvedTimelineScrollBehavior(totalLineCount: lineCount)
        switch behavior {
        case .native:
            timelineScrollOffset = 0
            let range = SloppyTUIScrollbackPolicy.nativeLineRange(behavior: behavior, totalLineCount: lineCount) ?? 0..<lineCount
            return slicedTimelineLines(segments, start: range.lowerBound, end: range.upperBound)
        case .viewport:
            let range = SloppyTUIScrollbackPolicy.viewportLineRange(behavior: behavior, totalLineCount: lineCount)
            if range.lowerBound > 0 || range.upperBound < lineCount {
                return clippedTimelineLines([slicedTimelineLines(segments, start: range.lowerBound, end: range.upperBound)], height: height)
            }
            return clippedTimelineLines(segments, height: height)
        }
    }

    func clippedTimelineLines(_ segments: [[String]], height: Int) -> [String] {
        let lineCount = segments.reduce(0) { $0 + $1.count }
        guard lineCount > height else {
            timelineScrollOffset = 0
            return segments.flatMap { $0 }
        }

        let maxOffset = max(0, lineCount - height)
        timelineScrollOffset = min(max(0, timelineScrollOffset), maxOffset)
        let end = lineCount - timelineScrollOffset
        let start = max(0, end - height)
        return slicedTimelineLines(segments, start: start, end: end)
    }

    func slicedTimelineLines(_ segments: [[String]], start: Int, end: Int) -> [String] {
        var visible: [String] = []
        visible.reserveCapacity(max(0, end - start))
        var segmentStart = 0
        for segment in segments {
            let segmentEnd = segmentStart + segment.count
            defer { segmentStart = segmentEnd }

            guard segmentEnd > start, segmentStart < end else {
                continue
            }

            let sliceStart = max(0, start - segmentStart)
            let sliceEnd = min(segment.count, end - segmentStart)
            visible.append(contentsOf: segment[sliceStart..<sliceEnd])
            if segmentEnd >= end {
                break
            }
        }
        return visible
    }

    func resolvedTimelineScrollBehavior(totalLineCount: Int) -> SloppyTUITimelineScrollBehavior {
        SloppyTUIScrollbackPolicy.behavior(
            mode: state.scrollbackMode,
            lineLimit: state.scrollbackLineLimit,
            totalLineCount: totalLineCount
        )
    }

    func renderMarkdown(_ text: String, width: Int) -> [String] {
        guard text.contains("```diff") else {
            return renderPlainMarkdown(text, width: width)
        }

        var lines: [String] = []
        var cursor = text.startIndex
        while let fenceStart = text[cursor...].range(of: "```diff") {
            appendPlainMarkdown(String(text[cursor..<fenceStart.lowerBound]), to: &lines, width: width)

            guard let firstNewline = text[fenceStart.upperBound...].firstIndex(of: "\n") else {
                cursor = fenceStart.upperBound
                continue
            }

            let diffStart = text.index(after: firstNewline)
            guard let fenceEnd = text[diffStart...].range(of: "```") else {
                lines.append(contentsOf: SloppyTUITheme.diffLines(String(text[diffStart...]), width: width))
                cursor = text.endIndex
                break
            }

            lines.append(contentsOf: SloppyTUITheme.diffLines(String(text[diffStart..<fenceEnd.lowerBound]), width: width))
            cursor = fenceEnd.upperBound
        }
        appendPlainMarkdown(String(text[cursor...]), to: &lines, width: width)
        return lines
    }

    func appendPlainMarkdown(_ text: String, to lines: inout [String], width: Int) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        if !lines.isEmpty {
            lines.append("")
        }
        lines.append(contentsOf: renderPlainMarkdown(text, width: width))
    }

    func renderPlainMarkdown(_ text: String, width: Int) -> [String] {
        let component = MarkdownComponent(
            text: text,
            padding: .init(horizontal: 1, vertical: 0),
            theme: timeline.theme
        )
        return component.render(width: width)
    }
}
