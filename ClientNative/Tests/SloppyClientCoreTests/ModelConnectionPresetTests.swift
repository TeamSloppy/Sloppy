import Testing
@testable import SloppyClientCore

struct ModelConnectionPresetTests {
    @Test func switchingToCodexClearsAPISecretsAndSelectsOAuth() {
        let original = SloppyConfig.ModelConfig(title: "My model", apiKey: "private-api-key", apiUrl: "https://api.example/v1", model: "openai-api:model")
        let codex = ModelConnectionPreset.codex.applying(to: original)
        #expect(codex.providerCatalogId == "openai-oauth")
        #expect(codex.apiKey.isEmpty)
        #expect(codex.model.isEmpty)
        #expect(codex.title == "My model")
    }

    @Test func selectingCurrentConnectionPreservesSettings() {
        let original = SloppyConfig.ModelConfig(title: "Remote", apiKey: "remote-token", apiUrl: "https://sloppy.example", model: "openai-oauth:model", providerCatalogId: "sloppy")
        let same = ModelConnectionPreset.sloppy.applying(to: original)
        #expect(same.apiKey == original.apiKey)
        #expect(same.apiUrl == original.apiUrl)
        #expect(same.model == original.model)
    }
}
