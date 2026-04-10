import Foundation
import Testing
@testable import sloppy

@Test
func coreModelProviderFactoryAcceptsOpenRouterPrefixedModel() {
    let model = CoreConfig.ModelConfig(
        title: "openrouter-main",
        apiKey: "",
        apiUrl: "",
        model: "openrouter:anthropic/claude-3.5-sonnet"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:anthropic/claude-3.5-sonnet")
}

@Test
func coreModelProviderFactoryInfersOpenRouterFromApiHost() {
    let model = CoreConfig.ModelConfig(
        title: "edge",
        apiKey: "sk-or-test",
        apiUrl: "https://openrouter.ai/api/v1",
        model: "openai/gpt-4o-mini"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:openai/gpt-4o-mini")
}
