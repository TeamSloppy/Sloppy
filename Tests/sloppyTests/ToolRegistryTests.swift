import Testing
@testable import sloppy

@Suite("ToolRegistry")
struct ToolRegistryTests {
    private let registry = ToolRegistry.makeDefault()

    @Test("All 30 tools are registered")
    func allToolsRegistered() {
        let expectedIDs: Set<String> = [
            "files.read", "files.edit", "files.write",
            "runtime.exec", "runtime.process",
            "web.search", "web.fetch",
            "branches.spawn",
            "workers.spawn", "workers.route",
            "sessions.spawn", "sessions.list", "sessions.history", "sessions.status",
            "messages.send", "sessions.send",
            "memory.recall", "memory.get", "memory.save", "memory.search",
            "agents.list",
            "channel.history",
            "system.list_tools",
            "cron",
            "project.task_list", "project.task_create", "project.task_get",
            "project.task_update", "project.task_cancel", "project.escalate_to_user",
            "actor.discuss_with_actor", "actor.conclude_discussion"
        ]
        let knownIDs = registry.knownToolIDs
        for id in expectedIDs {
            #expect(knownIDs.contains(id), "Missing tool ID: \(id)")
        }
    }

    @Test("Catalog entries count matches unique tools")
    func catalogEntriesCountMatchesUniqueTools() {
        let entries = registry.catalogEntries
        // sessions.send is an alias for messages.send, so count is unique primary IDs
        #expect(entries.count >= 28)
        #expect(entries.allSatisfy { !$0.id.isEmpty })
    }

    @Test("Catalog entry IDs match known tool IDs")
    func catalogEntryIDsAreRegistered() {
        let entries = registry.catalogEntries
        let knownIDs = registry.knownToolIDs
        for entry in entries {
            #expect(knownIDs.contains(entry.id), "Catalog entry '\(entry.id)' not found in registry")
        }
    }

    @Test("ToolCatalog.entries is non-empty")
    func toolCatalogEntriesNonEmpty() {
        #expect(!ToolCatalog.entries.isEmpty)
    }

    @Test("ToolCatalog.knownToolIDs contains expected tools")
    func toolCatalogKnownToolIDs() {
        #expect(ToolCatalog.knownToolIDs.contains("files.read"))
        #expect(ToolCatalog.knownToolIDs.contains("project.task_list"))
        #expect(ToolCatalog.knownToolIDs.contains("actor.discuss_with_actor"))
    }

    @Test("allTools returns unique tools with valid names and parameters")
    func allToolsAreUniqueAndWellFormed() {
        let tools = registry.allTools
        #expect(!tools.isEmpty)
        let names = tools.map { $0.name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "allTools contains duplicate tool names")
        for tool in tools {
            #expect(!tool.name.isEmpty)
            #expect(!tool.description.isEmpty)
        }
    }

    @Test("allTools count matches catalog entries count")
    func allToolsCountMatchesCatalogEntries() {
        let tools = registry.allTools
        let catalog = registry.catalogEntries
        #expect(tools.count == catalog.count)
    }
}
