import AnyLanguageModel
import Foundation
import Testing
@testable import AgentRuntime

private struct SizedTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema = String.generationSchema

    init(_ name: String, words: Int = 200) {
        self.name = name
        self.description = Array(repeating: "schema", count: words).joined(separator: " ")
    }

    func call(arguments: GeneratedContent) async throws -> String { "" }
}

private let catalog: [any Tool] = [
    SizedTool("browser.open"), SizedTool("sites.publish"), SizedTool("project.create"),
    SizedTool("files.read"), SizedTool("runtime.exec"), SizedTool("memory.search"),
    SizedTool("workspace.update"), SizedTool("session.complete"),
]

@Test
func toolSchemaBudgetKeepsEverythingWhenWindowIsLarge() {
    let selection = ToolSchemaBudget().select(from: catalog, windowTokens: 500_000)

    #expect(selection.tools.count == catalog.count)
    #expect(selection.droppedNames.isEmpty)
}

@Test
func toolSchemaBudgetDropsLowPriorityToolsFirstOnSmallWindow() {
    let one = ToolSchemaBudget.schemaTokens(of: catalog[0], estimator: TokenPressureEstimator())
    // Room for exactly four tools: three essential/preferred ones plus one other.
    let window = Int(Double(one * 4 + one / 2) / ToolSchemaBudget.defaultWindowFraction)

    let selection = ToolSchemaBudget().select(from: catalog, windowTokens: window)
    let names = Set(selection.tools.map(\.name))

    #expect(["files.read", "runtime.exec", "session.complete"].allSatisfy(names.contains))
    #expect(names.contains("memory.search"))
    #expect(selection.tools.count == 4)
    #expect(selection.droppedNames.count == catalog.count - 4)
    #expect(selection.schemaTokens <= Int(Double(window) * ToolSchemaBudget.defaultWindowFraction))
}

@Test
func toolSchemaBudgetNeverDropsEssentialToolsEvenOverBudget() {
    let selection = ToolSchemaBudget().select(from: catalog, windowTokens: 100)

    let names = Set(selection.tools.map(\.name))
    #expect(names == ["files.read", "runtime.exec", "session.complete"])
}
