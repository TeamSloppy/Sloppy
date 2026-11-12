import Foundation
import Testing
import Textual
@testable import SloppyClient

@Suite("Source syntax and working indicator")
@MainActor
struct SourceSyntaxTests {
    @Test func highlightsSwiftAndPreservesMultilineText() async {
        let text = "import Foundation\n/* comment\ncontinues */\nlet greeting = \"hello\"\nlet count = 42\n"
        let fixture = SourceFileFixture(content: text)
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift"), apiClient: fixture.api, scope: .project("project"))
        await model.loadIfNeeded()
        #expect(model.syntaxLines.count == model.lines.count)
        #expect(model.syntaxLines.map { $0.map(\.text).joined() } == model.lines)
        let runs = model.syntaxLines.flatMap { $0 }
        #expect(runs.contains { $0.kind == "keyword" && $0.text == "let" })
        #expect(runs.contains { $0.kind == "number" && $0.text == "42" })
        #expect(runs.contains { $0.kind == "string" && $0.text.contains("hello") })
        #expect(model.syntaxLines[2].contains { $0.kind == "comment" })
    }

    @Test func unsupportedLanguageRemainsPlainAndWorkingPulseIsBounded() {
        #expect(!SidebarSessionAvatar.shouldPulse(activity: .working, requiresApproval: false, reduceMotion: true))
        #expect(!SidebarSessionAvatar.shouldPulse(activity: .completed, requiresApproval: false, reduceMotion: false))
        #expect(!SidebarSessionAvatar.shouldPulse(activity: .working, requiresApproval: true, reduceMotion: false))
        #expect(SidebarSessionAvatar.shouldPulse(activity: .working, requiresApproval: false, reduceMotion: false))
        #expect(WorkspaceSourceFileViewModel.syntaxLanguage(for: "file.unknown") == nil)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(SidebarSessionAvatar.pulseOpacity(at: start, isActive: true) == 1)
        #expect(abs(SidebarSessionAvatar.pulseOpacity(at: start.addingTimeInterval(0.7), isActive: true) - 0.3) < 0.001)
        #expect(SidebarSessionAvatar.pulseOpacity(at: start.addingTimeInterval(0.7), isActive: false) == 1)
        #expect(SidebarSessionActivity.resolve(runStage: .thinking) == .working)
        #expect(SidebarSessionActivity.resolve(runStage: .done) == .completed)
    }
}
