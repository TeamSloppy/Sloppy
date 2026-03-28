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
        let cliAwareness = try templateLoader.loadPartial(named: "cli_awareness")
        let skillsEntries = buildSkillsEntries(skills: context.installedSkills)

        return Prompt {
            bootstrapMarker
            "Session context initialized."
            "Agent: \(context.agentID)"
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
            if !context.installedSkills.isEmpty {
                ""
                "[Skills]"
                skillsEntries
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
            cliAwareness
        }
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
