import AnyLanguageModel
import Foundation
import Protocols

struct SkillsSearchTool: CoreTool {
    let domain = "skills"
    let title = "Search skills registry"
    let status = "fully_functional"
    let name = "skills.search"
    let description = "Search the skills registry to discover available skills. Use this to find skills by name or keyword before installing."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "query", description: "Search query (e.g. 'obsidian', 'github', 'calendar')", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "sort", description: "Sort order: 'installs' (default), 'trending', 'recent'", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "limit", description: "Maximum number of results to return (default 10, max 20)", schema: DynamicGenerationSchema(type: Int.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.skillsService else {
            return toolFailure(tool: name, code: "not_available", message: "Skills service is unavailable.", retryable: true)
        }

        let query = arguments["query"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = arguments["sort"]?.asString ?? "installs"
        let limit = min(arguments["limit"]?.asInt ?? 10, 20)

        do {
            let response = try await svc.fetchSkillsRegistry(search: query?.isEmpty == false ? query : nil, sort: sort, limit: limit, offset: 0)
            let skillItems: [JSONValue] = response.skills.map { skill in
                .object([
                    "id": .string(skill.id),
                    "name": .string(skill.name),
                    "owner": .string(skill.owner),
                    "repo": .string(skill.repo),
                    "description": skill.description.map { .string($0) } ?? .null,
                    "installs": .number(Double(skill.installs)),
                    "githubUrl": .string(skill.githubUrl)
                ])
            }
            return toolSuccess(tool: name, data: .object([
                "skills": .array(skillItems),
                "total": .number(Double(response.total))
            ]))
        } catch {
            return toolFailure(tool: name, code: "registry_error", message: "Failed to fetch skills registry.", retryable: true)
        }
    }
}

struct SkillsListTool: CoreTool {
    let domain = "skills"
    let title = "List installed skills"
    let status = "fully_functional"
    let name = "skills.list"
    let description = "List all skills currently installed for this agent."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.skillsService else {
            return toolFailure(tool: name, code: "not_available", message: "Skills service is unavailable.", retryable: true)
        }

        do {
            let response = try await svc.listAgentSkills(agentID: context.agentID)
            let skillItems: [JSONValue] = response.skills.map { skill in
                .object([
                    "id": .string(skill.id),
                    "name": .string(skill.name),
                    "owner": .string(skill.owner),
                    "repo": .string(skill.repo),
                    "description": skill.description.map { .string($0) } ?? .null
                ])
            }
            return toolSuccess(tool: name, data: .object([
                "skills": .array(skillItems),
                "count": .number(Double(response.skills.count))
            ]))
        } catch {
            return toolFailure(tool: name, code: "list_error", message: "Failed to list installed skills.", retryable: true)
        }
    }
}

struct SkillsInstallTool: CoreTool {
    let domain = "skills"
    let title = "Install skill"
    let status = "fully_functional"
    let name = "skills.install"
    let description = "Install a skill for this agent from the registry, a GitHub repository, or a local directory containing SKILL.md. Use 'skills.search' first for registry/GitHub installs."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "owner", description: "GitHub repository owner. Optional for local installs; defaults to 'local'.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "repo", description: "GitHub repository name. Optional for local installs; defaults to the local skill directory or SKILL.md name.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "localPath", description: "Local directory path containing a skill (for example /path/to/my-skill with SKILL.md).", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.skillsService else {
            return toolFailure(tool: name, code: "not_available", message: "Skills service is unavailable.", retryable: true)
        }

        let owner = arguments["owner"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repo = arguments["repo"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localPath = arguments["localPath"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if localPath.isEmpty && (owner.isEmpty || repo.isEmpty) {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Provide either `localPath` or both `owner` and `repo`.", retryable: false)
        }

        let requestedID = localPath.isEmpty ? "\(owner)/\(repo)" : localPath
        do {
            let skill = try await svc.installAgentSkill(
                agentID: context.agentID,
                request: SkillInstallRequest(
                    owner: owner,
                    repo: repo,
                    localPath: localPath.isEmpty ? nil : localPath
                )
            )
            return toolSuccess(tool: name, data: .object([
                "id": .string(skill.id),
                "name": .string(skill.name),
                "owner": .string(skill.owner),
                "repo": .string(skill.repo),
                "description": skill.description.map { .string($0) } ?? .null,
                "localPath": .string(skill.localPath),
                "status": .string("installed")
            ]))
        } catch CoreService.AgentSkillsError.skillAlreadyExists {
            return toolFailure(tool: name, code: "already_installed", message: "Skill '\(requestedID)' is already installed.", retryable: false)
        } catch CoreService.AgentSkillsError.localPathFailure {
            return toolFailure(tool: name, code: "local_path_failed", message: "Failed to install local skill from '\(localPath)'. Ensure it is a directory containing SKILL.md.", retryable: false)
        } catch CoreService.AgentSkillsError.downloadFailure {
            return toolFailure(tool: name, code: "download_failed", message: "Failed to download skill '\(owner)/\(repo)' from GitHub.", retryable: true)
        } catch {
            return toolFailure(tool: name, code: "install_error", message: "Failed to install skill '\(requestedID)'.", retryable: true)
        }
    }
}

struct SkillsUninstallTool: CoreTool {
    let domain = "skills"
    let title = "Uninstall skill"
    let status = "fully_functional"
    let name = "skills.uninstall"
    let description = "Uninstall a previously installed skill from this agent. Use 'skills.list' to find the skill ID."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "skillId", description: "Skill ID to uninstall (format: owner/repo)", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.skillsService else {
            return toolFailure(tool: name, code: "not_available", message: "Skills service is unavailable.", retryable: true)
        }

        guard let skillID = arguments["skillId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines), !skillID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`skillId` is required.", retryable: false)
        }

        do {
            try await svc.uninstallAgentSkill(agentID: context.agentID, skillID: skillID)
            return toolSuccess(tool: name, data: .object([
                "skillId": .string(skillID),
                "status": .string("uninstalled")
            ]))
        } catch CoreService.AgentSkillsError.skillNotFound {
            return toolFailure(tool: name, code: "not_found", message: "Skill '\(skillID)' is not installed.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "uninstall_error", message: "Failed to uninstall skill '\(skillID)'.", retryable: true)
        }
    }
}
