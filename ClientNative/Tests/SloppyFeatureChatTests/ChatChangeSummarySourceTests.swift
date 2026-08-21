import Foundation
import Testing

@Suite("Chat change summary source")
struct ChatChangeSummarySourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("transcript renders source-control summary at the end of the completed turn")
    func transcriptRendersChangeSummary() throws {
        let screen = try source("Sources", "SloppyFeatureChat", "Screens", "Chat", "ChatScreen.swift")
        let summary = try source(
            "Sources", "SloppyFeatureChat", "Screens", "Chat", "Views", "ChatChangeSummaryView.swift"
        )

        #expect(screen.contains("content: .changeSummary(workingTreeSourceControl)"))
        #expect(screen.contains("ChatChangeSummaryView(sourceControl: sourceControl)"))
        #expect(summary.contains("Text(\"Review\")"))
        #expect(summary.contains("sourceControl.linesAdded"))
        #expect(summary.contains("sourceControl.linesDeleted"))
        #expect(summary.contains("ForEach(fileChanges)"))
        #expect(summary.contains("accessibilityIdentifier(\"chat.change-summary\")"))
    }

    @Test("view model refreshes changes from typed terminal run statuses")
    func viewModelRefreshesAtTerminalRunStatus() throws {
        let viewModel = try source(
            "Sources", "SloppyFeatureChat", "Screens", "Chat", "ChatScreenViewModel.swift"
        )

        #expect(viewModel.contains("case .paused, .done, .interrupted:"))
        #expect(viewModel.contains("refreshWorkingTreeSourceControl()"))
        #expect(viewModel.contains("fetchProjectWorkingTreeSourceControl(projectId: projectId)"))
        #expect(viewModel.contains("response?.hasChanges == true ? response : nil"))
    }
}
