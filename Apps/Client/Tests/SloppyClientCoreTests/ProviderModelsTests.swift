import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Provider models")
struct ProviderModelsTests {
    @Test("OpenCode model IDs decode without splitting provider namespaces")
    func decodesOpenCodeModelID() throws {
        let data = Data(#"[{"id":"opencode:openrouter-yandex-team/deepseek/deepseek-v4.1-flash","title":"DeepSeek V4.1 Flash","contextWindow":131072,"capabilities":["tools"]}]"#.utf8)

        let models = try JSONDecoder().decode([ProviderModelOption].self, from: data)

        #expect(models.count == 1)
        #expect(models[0].id == "opencode:openrouter-yandex-team/deepseek/deepseek-v4.1-flash")
        #expect(models[0].contextWindow == 131_072)
        #expect(models[0].capabilities == ["tools"])
    }

    @Test("catalog search is case-insensitive over full ID and title")
    func searchesFullModelIDAndTitle() {
        let model = ProviderModelOption(
            id: "opencode:openrouter-yandex-team/deepseek/deepseek-v4.1-flash",
            title: "DeepSeek V4.1 Flash"
        )

        #expect(model.matches(query: "OPENCODE:OPENROUTER-YANDEX-TEAM"))
        #expect(model.matches(query: "deepseek-v4.1"))
        #expect(model.matches(query: "v4.1 flash"))
        #expect(!model.matches(query: "claude"))
    }
}
