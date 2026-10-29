import Foundation
import Testing
@testable import SloppyClient
import SloppyClientCore

@Suite("Workspace chat drafts")
@MainActor
struct WorkspaceDraftTests {
    private func makeModel() throws -> MainViewModel {
        let url = try #require(URL(string: "http://127.0.0.1:25101"))
        return MainViewModel(baseURL: url, settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: url),
                             onOpenSettings: {}, onOpenWorkspace: {})
    }

    @Test("tabs preserve independent drafts when switching back and forth")
    func preservesIndependentDrafts() throws {
        let model = try makeModel()
        let first = model.navigation.selectedTabID
        model.chatViewModel.composerDraft.text = "First task"
        model.selectNewChat()
        let second = model.navigation.selectedTabID
        model.chatViewModel.composerDraft.text = "Second task"
        model.selectTab(first)
        #expect(model.chatViewModel.composerDraft.text == "First task")
        model.selectTab(second)
        #expect(model.chatViewModel.composerDraft.text == "Second task")
    }

    @Test("visiting Projects and Agents preserves the active conversation")
    func preservesChatAcrossSections() throws {
        let model = try makeModel()
        let chat = model.chatViewModel
        chat.composerDraft.text = "Continue here"
        model.selectSection(.projects)
        model.selectSection(.agents)
        model.selectSection(.chats)
        #expect(model.chatViewModel === chat)
        #expect(model.chatViewModel.composerDraft.text == "Continue here")
    }

    @Test("closing the last tab creates an empty draft with a new model")
    func closesFinalDraft() throws {
        let model = try makeModel()
        let old = model.chatViewModel
        old.composerDraft.text = "Old draft"
        model.closeTab(model.navigation.selectedTabID)
        #expect(model.chatViewModel !== old)
        #expect(model.chatViewModel.composerDraft.text.isEmpty)
        #expect(model.chatModels.count == 1)
    }
}
