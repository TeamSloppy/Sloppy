import Testing
@testable import sloppy

@Test
func promptTemplateRendererReplacesNamedPlaceholders() throws {
    let renderer = PromptTemplateRenderer()
    let output = try renderer.render(
        template: "Hello {{ name }} from {{city}}.",
        values: [
            "name": "Sloppy",
            "city": "Moscow"
        ]
    )

    #expect(output == "Hello Sloppy from Moscow.")
}

@Test
func promptTemplateRendererThrowsForMissingPlaceholder() throws {
    let renderer = PromptTemplateRenderer()

    #expect(throws: PromptTemplateRenderer.RenderError.self) {
        _ = try renderer.render(
            template: "Hello {{ name }} from {{city}}.",
            values: ["name": "Sloppy"]
        )
    }
}

@Test
func promptTemplateLoaderUsesInjectedResolver() throws {
    let loader = PromptTemplateLoader(resolver: { relativePath in
        switch relativePath {
        case "agent_session_bootstrap.md":
            return "bootstrap"
        case "partials/runtime_rules.md":
            return "rules"
        default:
            throw PromptTemplateLoader.LoaderError.templateNotFound(relativePath)
        }
    })

    #expect(try loader.loadTemplate(for: .agentSessionBootstrap) == "bootstrap")
    #expect(try loader.loadPartial(named: "runtime_rules") == "rules")
}
