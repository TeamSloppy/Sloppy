import Foundation
import Testing
import Protocols
@testable import sloppy

@Test
func resolveCanonicalAgentModelIDAcceptsPrefixedAndOpenRouterSlug() {
    let available = [
        ProviderModelOption(
            id: "openrouter:google/gemma-4-2-26b-a4b-it:free",
            title: "Gemma",
            capabilities: ["tools"]
        )
    ]
    #expect(
        CoreService.resolveCanonicalAgentModelID(
            "openrouter:google/gemma-4-2-26b-a4b-it:free",
            availableModels: available
        ) == "openrouter:google/gemma-4-2-26b-a4b-it:free"
    )
    #expect(
        CoreService.resolveCanonicalAgentModelID(
            "google/gemma-4-2-26b-a4b-it:free",
            availableModels: available
        ) == "openrouter:google/gemma-4-2-26b-a4b-it:free"
    )
}

@Test
func resolveCanonicalAgentModelIDRejectsAmbiguousSuffix() {
    let available = [
        ProviderModelOption(id: "openrouter:acme/foo", title: "A", capabilities: []),
        ProviderModelOption(id: "openai:acme/foo", title: "B", capabilities: [])
    ]
    #expect(CoreService.resolveCanonicalAgentModelID("acme/foo", availableModels: available) == nil)
}
