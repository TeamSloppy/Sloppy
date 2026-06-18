import Foundation
import Testing
@testable import ChannelPluginTelegram
import Protocols

@Test func telegramModelPicker_parseCallback_roundTrip() {
    let msgId: Int64 = 42
    #expect(TelegramModelPicker.callbackPage(messageId: msgId, page: 3).count <= TelegramModelPicker.maxCallbackBytes)
    #expect(TelegramModelPicker.callbackSelect(messageId: msgId, globalIndex: 15).count <= TelegramModelPicker.maxCallbackBytes)

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackPage(messageId: msgId, page: 2)) {
    case .page(let id, let p):
        #expect(id == msgId)
        #expect(p == 2)
    default:
        Issue.record("expected page")
    }

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackSelect(messageId: msgId, globalIndex: 9)) {
    case .select(let id, let i):
        #expect(id == msgId)
        #expect(i == 9)
    default:
        Issue.record("expected select")
    }

    if case .unknown = TelegramModelPicker.parseCallback("garbage") {
    } else {
        Issue.record("expected unknown")
    }
}

@Test func telegramModelPicker_groupsProvidersAndBuildsProviderKeyboard() {
    let models = [
        Provider("openai-oauth:gpt-5.5", "gpt-5.5"),
        Provider("openai-oauth:o4-mini", "o4-mini"),
        Provider("openrouter:google/gemma-4-26b-a4b-it:free", "google/gemma-4-26b-a4b-it:free"),
        Provider("ollama:gemma4:31b-cloud", "gemma4:31b-cloud"),
        Provider("custom-model", "custom-model")
    ]

    let providers = TelegramModelPicker.providerEntries(from: models)
    #expect(providers.map(\.id) == ["configured", "ollama", "openai-oauth", "openrouter"])

    let keyboard = TelegramModelPicker.buildProviderKeyboard(providers: providers, messageId: 77, page: 0)
    let labels = keyboard.flatMap { $0 }.compactMap { $0["text"] }
    #expect(labels.contains(where: { $0.hasPrefix("Configured") }))
    #expect(labels.contains(where: { $0.hasPrefix("Ollama") }))
    #expect(labels.contains(where: { $0.hasPrefix("OpenAI Codex") }))
    #expect(labels.contains(where: { $0.hasPrefix("OpenRouter") }))
}

@Test func telegramModelPicker_parseProviderAndBackCallbacks() {
    let msgId: Int64 = 42

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackProvider(messageId: msgId, providerId: "openai-oauth", page: 1)) {
    case .provider(let id, let providerId, let page):
        #expect(id == msgId)
        #expect(providerId == "openai-oauth")
        #expect(page == 1)
    default:
        Issue.record("expected provider callback")
    }

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackProvidersPage(messageId: msgId, page: 2)) {
    case .providersPage(let id, let page):
        #expect(id == msgId)
        #expect(page == 2)
    default:
        Issue.record("expected providers page callback")
    }

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackBackToProviders(messageId: msgId, page: 3)) {
    case .backToProviders(let id, let page):
        #expect(id == msgId)
        #expect(page == 3)
    default:
        Issue.record("expected back callback")
    }
}

@Test func telegramModelPicker_filtersModelsWithinSelectedProvider() {
    let models = [
        Provider("openai-oauth:gpt-5.5", "gpt-5.5"),
        Provider("openai-oauth:o4-mini", "o4-mini"),
        Provider("openrouter:openai/gpt-oss-20b:latest", "openai/gpt-oss-20b:latest")
    ]

    let filtered = TelegramModelPicker.filterModels(models, query: "gpt", providerId: "openai-oauth")
    #expect(filtered.map(\.id) == ["openai-oauth:gpt-5.5"])

    let allForProvider = TelegramModelPicker.filterModels(models, query: "", providerId: "openai-oauth")
    #expect(allForProvider.map(\.id) == ["openai-oauth:gpt-5.5", "openai-oauth:o4-mini"])
}

private func Provider(_ id: String, _ title: String) -> ProviderModelOption {
    ProviderModelOption(id: id, title: title)
}
