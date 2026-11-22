import Foundation
import SloppyClientCore
import SloppyClientUI
import Testing
@testable import SloppyFeatureChat

@MainActor
@Test
func acceptingPromptSuggestionInsertsOnlyAnEditableDraft() throws {
    let api = SloppyAPIClient()
    let viewModel = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
        settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
        restoresLastSession: false, responseNotificationScheduler: PromptSuggestionNotifications(), onOpenSettings: { _ in })
    let decoder = JSONDecoder()
    viewModel.activeRunStatus = try decoder.decode(ChatRunStatusEvent.self,
        from: Data(#"{"id":"done-run","stage":"done","label":"Done"}"#.utf8))
    viewModel.promptSuggestion = try decoder.decode(ChatPromptSuggestion.self,
        from: Data(#"{"sourceRunId":"old-run","text":"Stale prediction."}"#.utf8))
    #expect(viewModel.visiblePromptSuggestion == nil)
    viewModel.promptSuggestion = try decoder.decode(ChatPromptSuggestion.self,
        from: Data(#"{"sourceRunId":"done-run","text":"Make it shorter."}"#.utf8))
    #expect(viewModel.visiblePromptSuggestion == "Make it shorter.")
    let accepted = viewModel.acceptPromptSuggestion()
    #expect(accepted)
    #expect(viewModel.composerDraft.text == "Make it shorter.")
    #expect(!viewModel.isSending)
    #expect(viewModel.visiblePromptSuggestion == nil)
}

@MainActor
private final class PromptSuggestionNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
