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
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/ChatScreenViewModel.swift")
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

    @Test("project picker changes context without opening an existing session")
    func projectPickerChangesContextWithoutOpeningSession() throws {
        let source = try chatScreenViewModelSource
        let pickProjectStart = try #require(source.range(of: "public func pickProject("))
        let starterPromptStart = try #require(source.range(of: "public func useStarterPrompt("))
        let pickProjectSource = source[pickProjectStart.lowerBound..<starterPromptStart.lowerBound]

        #expect(pickProjectSource.contains("opensPreferredSession: false"))
        #expect(source.contains("guard opensPreferredSession else"))
    }

    @Test("new message opens an empty draft for the selected project")
    func newMessageOpensEmptyDraftForSelectedProject() throws {
        let source = try chatScreenViewModelSource
        let newMessageStart = try #require(source.range(of: "public func startNewMessage()"))
        let pickProjectStart = try #require(
            source.range(
                of: "public func pickProject(",
                range: newMessageStart.upperBound..<source.endIndex
            )
        )
        let newMessageSource = source[newMessageStart.lowerBound..<pickProjectStart.lowerBound]

        #expect(newMessageSource.contains("guard let projectId = activeProjectId"))
        #expect(newMessageSource.contains("activateProjectContext("))
        #expect(newMessageSource.contains("preferredTaskId: nil"))
        #expect(newMessageSource.contains("opensPreferredSession: false"))
        #expect(!newMessageSource.contains("createAgentSession("))
    }
}
