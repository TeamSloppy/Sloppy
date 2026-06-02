import Protocols
import Testing
@testable import sloppy

@Test
func subagentEffectiveToolsAppliesDenylist() {
    let policy = AgentToolsPolicy(defaultPolicy: .allow, tools: [:])
    let known: Set<String> = [
        "workers.spawn",
        "files.read",
        "memory.save",
        "agents.delegate_task",
        "agent_delegate.finish",
    ]
    let eff = SubagentDelegation.effectiveToolIDs(
        policy: policy,
        knownToolIDs: known,
        toolsetNames: nil
    )
    #expect(!eff.contains("workers.spawn"))
    #expect(!eff.contains("memory.save"))
    #expect(!eff.contains("agents.delegate_task"))
    #expect(eff.contains("agent_delegate.finish"))
    #expect(eff.contains("files.read"))
}

@Test
func subagentEffectiveToolsIntersectsToolsets() {
    let policy = AgentToolsPolicy(defaultPolicy: .allow, tools: [:])
    let known: Set<String> = ["files.read", "web.search", "workers.spawn", "runtime.process", "agent_delegate.finish"]
    let eff = SubagentDelegation.effectiveToolIDs(
        policy: policy,
        knownToolIDs: known,
        toolsetNames: ["file"]
    )
    #expect(eff == Set(["files.read", "agent_delegate.finish"]))
}

@Test
func subagentTerminalToolsetDropsBlockedExec() {
    let policy = AgentToolsPolicy(defaultPolicy: .allow, tools: [:])
    let known: Set<String> = ["runtime.exec", "runtime.process"]
    let eff = SubagentDelegation.effectiveToolIDs(
        policy: policy,
        knownToolIDs: known,
        toolsetNames: ["terminal"]
    )
    #expect(!eff.contains("runtime.exec"))
    #expect(eff.contains("runtime.process"))
}

@Test
func subagentProjectTasksToolsetAllowsOnlyTaskLifecycleTools() {
    let policy = AgentToolsPolicy(defaultPolicy: .allow, tools: [:])
    let known: Set<String> = [
        "project.current",
        "project.task_list",
        "project.task_create",
        "project.task_get",
        "project.task_update",
        "project.delete",
        "agent_delegate.finish",
    ]
    let eff = SubagentDelegation.effectiveToolIDs(
        policy: policy,
        knownToolIDs: known,
        toolsetNames: ["project_tasks"]
    )
    #expect(eff == Set([
        "project.current",
        "project.task_list",
        "project.task_create",
        "project.task_get",
        "project.task_update",
        "agent_delegate.finish",
    ]))
}

@Test
func subagentRespectsParentDenyPolicy() {
    let policy = AgentToolsPolicy(
        defaultPolicy: .allow,
        tools: ["files.read": false, "web.search": true]
    )
    let known: Set<String> = ["files.read", "web.search"]
    let eff = SubagentDelegation.effectiveToolIDs(
        policy: policy,
        knownToolIDs: known,
        toolsetNames: nil
    )
    #expect(!eff.contains("files.read"))
    #expect(eff.contains("web.search"))
}
