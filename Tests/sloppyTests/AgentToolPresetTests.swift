import Foundation
import Testing
@testable import sloppy

private let known: Set<String> = [
    "files.read", "runtime.exec", "session.complete", "project.current", "project.task_list",
    "project.create", "browser.open", "browser.screenshot", "cron", "sites.publish", "mcp.call_tool",
    "mcp.install_server", "workspace.update", "images.generate", "agent.documents.set_memory_markdown",
]

@Test
func codingPresetDeniesRarelyUsedGroupsAndKeepsCodingTools() {
    let tools = AgentToolPreset.coding.apply(to: [:], knownToolIDs: known)

    for denied in ["browser.open", "browser.screenshot", "cron", "sites.publish", "mcp.install_server",
                   "workspace.update", "images.generate", "project.create", "agent.documents.set_memory_markdown"] {
        #expect(tools[denied] == false, "\(denied) should be denied")
    }
    for kept in ["files.read", "runtime.exec", "session.complete", "project.current", "project.task_list", "mcp.call_tool"] {
        #expect(tools[kept] == nil, "\(kept) must stay allowed")
    }
}

@Test
func codingPresetPreservesUnrelatedEntriesAndIsIdempotent() {
    let existing = ["files.write": false, "web.search": true]

    let once = AgentToolPreset.coding.apply(to: existing, knownToolIDs: known)
    let twice = AgentToolPreset.coding.apply(to: once, knownToolIDs: known)

    #expect(once["files.write"] == false)
    #expect(once["web.search"] == true)
    #expect(once == twice)
}

@Test
func fullPresetRestoresOnlyTheDenialsThePresetManages() {
    let coding = AgentToolPreset.coding.apply(to: ["files.write": false, "browser.open": true], knownToolIDs: known)

    let restored = AgentToolPreset.full.apply(to: coding, knownToolIDs: known)

    #expect(restored["browser.open"] == nil || restored["browser.open"] == true)
    #expect(restored["cron"] == nil)
    #expect(restored["sites.publish"] == nil)
    #expect(restored["files.write"] == false)
}
