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

    func compose(context: PromptRenderContext) throws -> String {
        switch context.processKind {
        case .agentSessionBootstrap:
            return try composeAgentSessionBootstrap(context: context)
        case .swarmPlanner:
            throw ComposerError.unsupportedProcess
        }
    }

    private func composeAgentSessionBootstrap(context: PromptRenderContext) throws -> String {
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
        let memoryRules = try templateLoader.loadPartial(named: "memory_rules")
        let skillsEntries = buildSkillsEntries(skills: context.installedSkills)

        let instructions = Instructions {
            bootstrapMarker
            "Session context initialized."
            "Agent: \(context.agentID)"
            "Session: \(sessionID)"

            if !documents.agentsMarkdown.isEmpty {
                ""
                "[Agents.md]"
                documents.agentsMarkdown
            }
            if !documents.userMarkdown.isEmpty {
                ""
                "[User.md]"
                documents.userMarkdown
            }
            if !documents.identityMarkdown.isEmpty {
                ""
                "[Identity.md]"
                documents.identityMarkdown
            }
            if !documents.soulMarkdown.isEmpty {
                ""
                "[Soul.md]"
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
            memoryRules
        }

        return instructions.description
    }

    private func buildSkillsEntries(skills: [InstalledSkill]) -> String {
        skills
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { skill in
                let description = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if description.isEmpty {
                    return "- `\(skill.id)` | \(skill.name) | path: `\(skill.localPath)`"
                }
                return "- `\(skill.id)` | \(skill.name) | \(description) | path: `\(skill.localPath)`"
            }
            .joined(separator: "\n")
    }
}
