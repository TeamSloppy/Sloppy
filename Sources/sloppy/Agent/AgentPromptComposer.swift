import Foundation
import AnyLanguageModel
import Protocols

struct AgentPromptComposer {
    enum ComposerError: Error {
        case unsupportedProcess
    }

    private let templateLoader: PromptTemplateLoader

    init(templateLoader: PromptTemplateLoader = PromptTemplateLoader()) {
        self.templateLoader = templateLoader
    }

    func compose(context: PromptRenderContext) throws -> Prompt {
        switch context.processKind {
        case .agentSessionBootstrap:
            return try composeAgentSessionBootstrap(context: context)
        case .swarmPlanner:
            throw ComposerError.unsupportedProcess
        }
    }

    private func composeAgentSessionBootstrap(context: PromptRenderContext) throws -> Prompt {
        guard let sessionID = context.sessionID,
              let bootstrapMarker = context.bootstrapMarker,
              let documents = context.documents
        else {
            throw ComposerError.unsupportedProcess
        }

        let capabilities = try templateLoader.loadPartial(named: "session_capabilities")
        let runtimeRules = try templateLoader.loadPartial(named: "runtime_rules")
        let branchingRules = try templateLoader.loadPartial(named: "branching_rules")
        let workerRules = try templateLoader.loadPartial(named: "worker_rules")
        let toolsInstruction = try templateLoader.loadPartial(named: "tools_instruction")
        let skillsRules = try templateLoader.loadPartial(named: "skills_rules")
        let memoryRules = try templateLoader.loadPartial(named: "memory_rules")
        let taskPlanningRules = try templateLoader.loadPartial(named: "task_planning_rules")
        let taskSpecRules = try templateLoader.loadPartial(named: "task_spec_rules")
        let completionReflection = try templateLoader.loadPartial(named: "completion_reflection")
        let cliAwareness = try templateLoader.loadPartial(named: "cli_awareness")
        let documentationAwareness = try templateLoader.loadPartial(named: "documentation_awareness")
        let skillsEntries = buildSkillsEntries(skills: context.installedSkills)

        return Prompt {
            bootstrapMarker
            "Session context initialized."
            "Agent: \(context.agentID)"
            if let agentDirectoryPath = context.agentDirectoryPath,
               !agentDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                "Agent directory: \(agentDirectoryPath)"
            }
            "Current session ID: \(sessionID)"

            if !documents.agentsMarkdown.isEmpty {
                ""
                "[AGENTS.md]"
                documents.agentsMarkdown
            }
            if !documents.userMarkdown.isEmpty {
                ""
                "[USER.md]"
                documents.userMarkdown
            }
            if !documents.identityMarkdown.isEmpty {
                ""
                "[IDENTITY.md]"
                documents.identityMarkdown
            }
            if !documents.soulMarkdown.isEmpty {
                ""
                "[SOUL.md]"
                documents.soulMarkdown
            }
            if !documents.memoryMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ""
                "[MEMORY.md]"
                documents.memoryMarkdown
            }
            if !context.installedSkills.isEmpty {
                ""
                "[Skills]"
                buildSkillsPrompt(entries: skillsEntries)
            }
            ""
            capabilities
            ""
            runtimeRules
            ""
            branchingRules
            ""
            workerRules
            ""
            toolsInstruction
            ""
            skillsRules
            ""
            memoryRules
            ""
            taskPlanningRules
            ""
            taskSpecRules
            ""
            completionReflection
            ""
            cliAwareness
            ""
            documentationAwareness
        }
    }

    func buildSkillsPrompt(entries: String) -> String {
        """
        ## Skills (mandatory)
        Before replying, scan the skills below. If a skill matches or is even partially relevant to your task, you MUST read it before answering and follow its instructions.
        Err on the side of loading — it is always better to have context you do not need than to miss critical steps, pitfalls, or established workflows.
        Skills contain specialized knowledge, tool-specific commands, proven workflows, and the user's preferred conventions and quality standards. Load the skill even if you think you could handle the task with basic tools.
        Use `files.read` on the skill path plus `/SKILL.md`; do not proceed without loading a genuinely relevant skill.
        If a loaded skill is missing steps, has wrong commands, or lacks pitfalls you discovered, mention that it should be updated before finishing.
        After difficult or iterative tasks, offer to save the workflow as a skill.

        <available_skills>
        \(entries)
        </available_skills>

        Only proceed without loading a skill if genuinely none are relevant to the task.
        """
    }

    func buildSkillsEntries(skills: [InstalledSkill]) -> String {
        skills
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { skill in
                var parts: [String] = ["`\(skill.id)`", skill.name]
                let description = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !description.isEmpty {
                    parts.append(description)
                }
                if !skill.userInvocable {
                    parts.append("user-invocable: false")
                }
                if !skill.allowedTools.isEmpty {
                    parts.append("allowed-tools: \(skill.allowedTools.joined(separator: ", "))")
                }
                if let ctx = skill.context {
                    parts.append("context: \(ctx.rawValue)")
                }
                if let agent = skill.agent, !agent.isEmpty {
                    parts.append("agent: \(agent)")
                }
                parts.append("path: `\(skill.localPath)`")
                return "- " + parts.joined(separator: " | ")
            }
            .joined(separator: "\n")
    }
}
