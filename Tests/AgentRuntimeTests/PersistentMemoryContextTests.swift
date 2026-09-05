import Foundation
import Testing
@testable import AgentRuntime
import Protocols

@Test
func persistentMemoryCrossesSessionsOnlyThroughExplicitScopes() async {
    let memory = InMemoryMemoryStore()
    for (note, scope) in [
        ("Aurora uses SQLite", MemoryScope.agent("helper")),
        ("Aurora builds with Swift", .project("aurora")),
        ("Aurora private old chat", .channel("agent:helper:session:old")),
        ("Aurora other agent", .agent("other")),
        ("Aurora other project", .project("other"))
    ] {
        _ = await memory.save(entry: MemoryWriteRequest(note: note, memoryClass: .semantic, scope: scope))
    }
    let runtime = RuntimeSystem(memoryStore: memory)
    let channel = "agent:helper:session:new"
    await runtime.setMemoryProject(channelId: channel, projectID: "aurora")
    let snapshot = await runtime.persistentMemoryContext(channelId: channel)
    let recalled = await runtime.userMessageWithAutoRecalledMemory(channelId: channel, userMessage: "Aurora")
    for context in [snapshot, recalled] {
        #expect(context.contains("Aurora uses SQLite"))
        #expect(context.contains("Aurora builds with Swift"))
        #expect(!context.contains("private old chat"))
        #expect(!context.contains("other agent"))
        #expect(!context.contains("other project"))
    }
    await runtime.setMemoryProject(channelId: channel, projectID: nil)
    let unscoped = await runtime.persistentMemoryContext(channelId: channel)
    #expect(!unscoped.contains("builds with Swift"))
}

@Test
func persistentMemorySnapshotIsBoundedAndPrioritizesPreferences() async {
    let memory = InMemoryMemoryStore()
    for index in 0..<40 {
        _ = await memory.save(entry: MemoryWriteRequest(
            note: "Fact \(index): " + String(repeating: "detail ", count: 100),
            kind: .fact, memoryClass: .semantic, scope: .agent("helper")
        ))
    }
    _ = await memory.save(entry: MemoryWriteRequest(
        note: "User prefers focused checks", kind: .preference,
        memoryClass: .semantic, scope: .agent("helper")
    ))
    let runtime = RuntimeSystem(memoryStore: memory)
    let context = await runtime.persistentMemoryContext(channelId: "agent:helper:session:new", maxCharacters: 1000)
    #expect(context.count <= 1000)
    #expect(context.contains("User prefers focused checks"))
    #expect(await runtime.persistentMemoryContext(channelId: "agent:helper:session:new", maxCharacters: 0) == "")
    #expect(await runtime.persistentMemoryContext(channelId: "agent:helper:session:new:memory-checkpoint:1") == "")
}
