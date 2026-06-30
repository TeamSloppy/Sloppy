import Foundation
import Testing

@Suite("Chat task navigation source")
struct ChatTaskNavigationSourceTests {
    private var chatScreenViewModelSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatScreenViewModel.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("task navigation keeps an empty draft until the first send")
    func taskNavigationKeepsAnEmptyDraftUntilTheFirstSend() throws {
        let source = try chatScreenViewModelSource

        #expect(source.contains("private var activeTaskId: String?"))
        #expect(source.contains("activeTaskId = preferredTaskId"))
        #expect(source.contains("let sessionTitle = taskId.map(taskSessionTitle(for:)) ?? contextTitle ??"))
        #expect(source.contains("title: activeTaskId.map(taskSessionTitle(for:)) ?? activeContextTitle ??"))

        let activateStart = try #require(source.range(of: "private func activateProjectContext("))
        let disconnectStart = try #require(source.range(of: "    private func disconnectCurrentSession()"))
        let activateSource = source[activateStart.lowerBound..<disconnectStart.lowerBound]

        #expect(!activateSource.contains("createAgentSession("))
    }
}
