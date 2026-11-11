import Protocols
import TauTUI

@MainActor
extension SloppyTUIScreen {
    var latestBuildProgress: AgentBuildProgressEvent? {
        sessionCards.reversed().compactMap { block in
            if case .buildProgress(let progress) = block { return progress }
            return nil
        }.first
    }

    func renderChatBody(width: Int, height: Int, startColumn: Int = 0) -> [String] {
        let progress = latestBuildProgress
        let hasContext = progress != nil || workspaceDiffPreview != nil
        guard let paneWidth = SloppyTUIChangesPane.width(for: width, hasChanges: hasContext) else {
            guard let progress else {
                return renderChatTimelineBody(width: width, height: height)
            }
            // Keep goals pinned outside scrollback even when two columns do not fit.
            let goalsHeight = min(max(1, height - 3), max(2, height / 3))
            let goals = renderGoalsPane(progress, width: width, height: goalsHeight,
                                        startRow: 0, startColumn: startColumn)
            let chatHeight = max(0, height - goalsHeight)
            let chat = renderChatTimelineBody(width: width, height: max(1, chatHeight))
            return goals + SloppyTUITheme.normalize(lines: chat, width: width, height: chatHeight)
        }
        let chatWidth = width - paneWidth - 1
        let chat = renderChatTimelineBody(width: chatWidth, height: height, hidesDiff: true)
        let paneColumn = startColumn + chatWidth + 1
        var context: [String] = []
        if let progress {
            let goalsHeight = workspaceDiffPreview == nil ? height : max(1, height / 2)
            context = renderGoalsPane(progress, width: paneWidth, height: goalsHeight,
                                      startRow: 0, startColumn: paneColumn)
        }
        if let preview = workspaceDiffPreview, context.count < height {
            let diffHeight = height - context.count
            let diffLines = renderTimelineLines([preview.timelineBlock], width: paneWidth)
            let contentHeight = max(0, diffHeight - 1)
            workspaceDiffScrollOffset = min(workspaceDiffScrollOffset, max(0, diffLines.count - contentHeight))
            registerScrollRegion(startRow: context.count, endRow: height, startColumn: paneColumn,
                                 endColumn: startColumn + width, target: .workspaceDiff)
            context += [SloppyTUITheme.fittedLine("Changes · scroll to review", width: paneWidth)]
                + Array(diffLines.dropFirst(workspaceDiffScrollOffset).prefix(contentHeight))
        }
        return Self.zippedPaneLines(left: chat, right: context, leftWidth: chatWidth,
                                    rightWidth: paneWidth, separator: "│", height: height)
    }

    func renderGoalsPane(_ progress: AgentBuildProgressEvent, width: Int, height: Int,
                         startRow: Int, startColumn: Int) -> [String] {
        let lines = SloppyTUITheme.buildProgressLines(progress, width: width)
        let contentHeight = max(0, height - 1)
        buildProgressScrollOffset = min(buildProgressScrollOffset, max(0, lines.count - contentHeight))
        let content = [SloppyTUITheme.fittedLine("Goals · scroll to review", width: width)]
            + Array(lines.dropFirst(buildProgressScrollOffset).prefix(contentHeight))
        registerScrollRegion(startRow: startRow, endRow: startRow + height, startColumn: startColumn,
                             endColumn: startColumn + width, target: .buildProgress)
        return SloppyTUITheme.normalize(lines: content, width: width, height: height)
    }
}
