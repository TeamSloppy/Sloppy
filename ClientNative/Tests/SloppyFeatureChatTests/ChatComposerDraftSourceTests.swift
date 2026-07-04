import Foundation
import Testing

@Suite("Chat composer draft source")
struct ChatComposerDraftSourceTests {
    private var viewModelSource: String {
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

    @Test("view model stores composer drafts per active session or draft context")
    func viewModelStoresComposerDraftsPerActiveSessionOrDraftContext() throws {
        let source = try viewModelSource

        #expect(source.contains("private var composerDraftsByKey: [String: String] = [:]"))
        #expect(source.contains("private var activeComposerDraftKey: String?"))
        #expect(source.contains("private func syncComposerDraft("))
        #expect(source.contains("private func composerDraftKey("))
        #expect(source.contains("return \"session:\\(sessionId)\""))
        #expect(source.contains("return \"draft:\\(resolvedAgentId):\\(projectId ?? \"-\"):\\(taskId ?? \"-\")\""))
    }

    @Test("send message clears the active composer draft and dismisses focus")
    func sendMessageClearsActiveComposerDraftAndDismissesFocus() throws {
        let source = try viewModelSource

        #expect(source.contains("clearActiveComposerDraft()"))
        #expect(source.contains("dismissComposerFocus()"))
        #expect(source.contains("private func clearActiveComposerDraft()"))
        #expect(source.contains("composerDraft.text = \"\""))
    }
}
