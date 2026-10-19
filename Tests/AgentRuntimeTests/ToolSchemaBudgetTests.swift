import AnyLanguageModel
import Foundation
import Testing
@testable import AgentRuntime
@testable import PluginSDK

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

@Test func toolSchemaBudgetPrioritizesDefaultMCPPathOverOptionalSearch() {
    let tools: [any Tool] = [
        SizedTool("system.search_tools"),
        SizedTool("mcp.list_tools"),
        SizedTool("mcp.call_tool"),
    ]
    let estimator = TokenPressureEstimator()
    let defaultPathCost = tools.dropFirst().reduce(0) {
        $0 + ToolSchemaBudget.schemaTokens(of: $1, estimator: estimator)
    }
    let selection = ToolSchemaBudget(windowFraction: 1).select(from: tools, windowTokens: defaultPathCost)
    #expect(Set(selection.tools.map(\.name)) == ["mcp.list_tools", "mcp.call_tool"])
    #expect(selection.droppedNames == ["system.search_tools"])

    let allCost = defaultPathCost + ToolSchemaBudget.schemaTokens(of: tools[0], estimator: estimator)
    let ample = ToolSchemaBudget(windowFraction: 1).select(from: tools, windowTokens: allCost)
    #expect(ample.tools.map(\.name) == tools.map(\.name))
    #expect(ample.droppedNames.isEmpty)
}

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

@Test
func policyExcludedToolsAreWithheldFromModelSchemas() async {
    let tools: [any Tool] = [SizedTool("files.read", words: 5), SizedTool("browser.open", words: 5), SizedTool("session.complete", words: 5)]
    let provider = CompositeModelProvider(providers: [], tools: tools)
    let runtime = RuntimeSystem(modelProvider: provider)

    let changed = await runtime.setChannelExcludedTools(channelId: "c", toolIDs: ["browser.open"])
    let unchanged = await runtime.setChannelExcludedTools(channelId: "c", toolIDs: ["browser.open"])
    let visible = await runtime.filteredModelTools(channelId: "c", modelProvider: provider, includeTools: true)
    let otherChannel = await runtime.filteredModelTools(channelId: "other", modelProvider: provider, includeTools: true)

    #expect(changed)
    #expect(!unchanged)
    #expect(visible.map(\.name) == ["files.read", "session.complete"])
    #expect(otherChannel.count == 3)

    await runtime.setChannelExcludedTools(channelId: "c", toolIDs: [])
    #expect(await runtime.filteredModelTools(channelId: "c", modelProvider: provider, includeTools: true).count == 3)
}

@Test
func explicitAllowListWinsOverPolicyExclusions() async {
    let tools: [any Tool] = [SizedTool("files.read", words: 5), SizedTool("browser.open", words: 5)]
    let provider = CompositeModelProvider(providers: [], tools: tools)
    let runtime = RuntimeSystem(modelProvider: provider)
    await runtime.setChannelToolAllowList(channelId: "c", toolIDs: ["browser.open"])
    await runtime.setChannelExcludedTools(channelId: "c", toolIDs: ["files.read"])

    let visible = await runtime.filteredModelTools(channelId: "c", modelProvider: provider, includeTools: true)

    #expect(visible.map(\.name) == ["browser.open"])
}
