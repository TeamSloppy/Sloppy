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

struct SkillsManageTool: CoreTool {
    let domain = "skills"
    let title = "Create or update skill"
    let status = "fully_functional"
    let name = "skills.manage"
    let description = "Create or update a skill in this agent's skills directory. Writes SKILL.md plus optional bundled files under the skill folder."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "repo", description: "Skill folder/repo name, normalized to a safe skill ID component.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "skillMarkdown", description: "Complete SKILL.md content, including YAML frontmatter with name and description.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "owner", description: "Skill owner namespace. Defaults to 'local'.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(
                name: "files",
                description: "Additional UTF-8 text files as objects with path and content, for example [{\"path\":\"references/guide.md\",\"content\":\"...\"}]. SKILL.md is ignored here; use skillMarkdown.",
                schema: DynamicGenerationSchema(
                    arrayOf: DynamicGenerationSchema(
                        name: "SkillSaveFile",
                        properties: [
                            .init(name: "path", description: "Safe relative path under the skill directory.", schema: DynamicGenerationSchema(type: String.self)),
                            .init(name: "content", description: "UTF-8 text content to write.", schema: DynamicGenerationSchema(type: String.self))
                        ]
                    )
                ),
                isOptional: true
            ),
            .init(name: "userInvocable", description: "Whether users can invoke this skill directly. Defaults to SKILL.md frontmatter or true.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
            .init(name: "allowedTools", description: "Optional tool IDs this skill expects. Defaults to SKILL.md frontmatter.", schema: DynamicGenerationSchema(type: [String].self), isOptional: true),
            .init(name: "context", description: "Optional skill context, currently 'fork' when the skill should run in a forked agent context.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "agent", description: "Optional preferred agent/role metadata for the skill.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "autoRoute", description: "Optional auto-route metadata for runtime routing.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let svc = context.skillsService else {
            return toolFailure(tool: name, code: "not_available", message: "Skills service is unavailable.", retryable: true)
        }

        guard let repo = arguments["repo"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`repo` is required.", retryable: false)
        }
        guard let skillMarkdown = arguments["skillMarkdown"]?.asString, !skillMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`skillMarkdown` is required.", retryable: false)
        }

        let owner = arguments["owner"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "local"
        let userInvocable = arguments["userInvocable"]?.asBool
        let allowedTools = arguments["allowedTools"]?.asArray?.compactMap(\.asString)
        let contextValue: SkillContext? = {
            guard let raw = arguments["context"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else {
                return nil
            }
            return SkillContext(rawValue: raw)
        }()
        let files: [String: String]
        do {
            files = try parseExtraFiles(arguments["files"])
        } catch {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "`files` must be an object of safe relative paths to string content.",
                retryable: false
            )
        }

        do {
            let result = try await svc.saveAgentSkill(
                agentID: context.agentID,
                request: SkillSaveRequest(
                    owner: owner.isEmpty ? "local" : owner,
                    repo: repo,
                    skillMarkdown: skillMarkdown,
                    files: files,
                    userInvocable: userInvocable,
                    allowedTools: allowedTools,
                    context: contextValue,
                    agent: arguments["agent"]?.asString,
                    autoRoute: arguments["autoRoute"]?.asString
                )
            )
            let skill = result.skill
            return toolSuccess(tool: name, data: .object([
                "id": .string(skill.id),
                "name": .string(skill.name),
                "owner": .string(skill.owner),
                "repo": .string(skill.repo),
                "description": skill.description.map { .string($0) } ?? .null,
                "localPath": .string(skill.localPath),
                "status": .string(result.created ? "created" : "updated")
            ]))
        } catch CoreService.AgentSkillsError.invalidPayload {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Provide a valid `repo` and `skillMarkdown`.", retryable: false)
        } catch CoreService.AgentSkillsError.agentNotFound {
            return toolFailure(tool: name, code: "agent_not_found", message: "Agent '\(context.agentID)' was not found.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "save_error", message: "Failed to save skill '\(owner)/\(repo)'.", retryable: true)
        }
    }

    private func parseExtraFiles(_ value: JSONValue?) throws -> [String: String] {
        guard let value else { return [:] }
        var files: [String: String] = [:]

        if let object = value.asObject {
            for (relativePath, contentValue) in object {
                guard isSafeSkillRelativePath(relativePath), let content = contentValue.asString else {
                    throw SkillsManageToolError.invalidFiles
                }
                files[relativePath] = content
            }
            return files
        }

        guard let array = value.asArray else { throw SkillsManageToolError.invalidFiles }
        for item in array {
            guard let object = item.asObject,
                  let relativePath = object["path"]?.asString,
                  let content = object["content"]?.asString,
                  isSafeSkillRelativePath(relativePath)
            else {
                throw SkillsManageToolError.invalidFiles
            }
            files[relativePath] = content
        }
        return files
    }

    private func isSafeSkillRelativePath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !components.isEmpty &&
            relativePath != "SKILL.md" &&
            components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private enum SkillsManageToolError: Error {
    case invalidFiles
}
