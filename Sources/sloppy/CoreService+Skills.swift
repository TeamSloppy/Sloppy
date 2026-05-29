import ChannelPluginSupport
import Foundation
import Logging
import Protocols

// MARK: - Skills

extension CoreService {
    /// Fetch skills from skills.sh registry
    public func fetchSkillsRegistry(search: String? = nil, sort: String = "installs", limit: Int = 20, offset: Int = 0) async throws -> SkillsRegistryResponse {
        logger.debug("[skills.registry] request: search=\(search ?? "nil"), sort=\(sort), limit=\(limit), offset=\(offset)")

        let response: SkillsRegistryResponse
        do {
            let sortOption: SkillsRegistryService.SortOption
            switch sort {
            case "trending":
                sortOption = .trending
            case "recent":
                sortOption = .recent
            default:
                sortOption = .installs
            }
            response = try await skillsRegistryService.fetchSkills(search: search, sort: sortOption, limit: limit, offset: offset)
        } catch {
            logger.warning("[skills.registry] registry fetch failed, using mock data: \(String(describing: error))")
            response = skillsRegistryService.fetchMockSkills(search: search, limit: limit, offset: offset)
        }

        if let jsonData = try? JSONEncoder().encode(response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let preview = jsonString.count > 1500 ? String(jsonString.prefix(1500)) + "…" : jsonString
            logger.debug("[skills.registry] response: total=\(response.total), skillsCount=\(response.skills.count), json=\(preview)")
        } else {
            logger.debug("[skills.registry] response: total=\(response.total), skillsCount=\(response.skills.count)")
        }
        return response
    }

    /// List installed skills for an agent
    public func listAgentSkills(agentID: String) async throws -> AgentSkillsResponse {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)

        do {
            try agentSkillsStore.provisionBuiltInSkills(agentID: normalizedAgentID)
            let skills = try agentSkillsStore.listSkills(agentID: normalizedAgentID)
            let skillsPath = agentSkillsStore.skillsDirectoryURL(agentID: normalizedAgentID)?.path ?? ""
            return AgentSkillsResponse(agentId: normalizedAgentID, skills: skills, skillsPath: skillsPath)
        } catch let error as AgentSkillsFileStore.StoreError {
            throw mapAgentSkillsError(error)
        } catch {
            throw AgentSkillsError.storageFailure
        }
    }

    /// Install a skill for an agent
    public func installAgentSkill(agentID: String, request: SkillInstallRequest) async throws -> InstalledSkill {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)

        let localPath = request.localPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = request.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = request.repo.trimmingCharacters(in: .whitespacesAndNewlines)

        let installingLocalSkill = localPath?.isEmpty == false
        if !installingLocalSkill, (owner.isEmpty || repo.isEmpty) {
            throw AgentSkillsError.invalidPayload
        }

        do {
            let existingSkills = try agentSkillsStore.listSkills(agentID: normalizedAgentID)

            let downloadedSkill: SkillsGitHubClient.DownloadedSkill
            if let localPath, !localPath.isEmpty {
                let localRepo = repo.isEmpty ? Self.defaultLocalSkillRepo(from: localPath) : repo
                let skillID = "\(owner.isEmpty ? "local" : owner)/\(localRepo)"
                if existingSkills.contains(where: { $0.id == skillID }) {
                    throw AgentSkillsError.skillAlreadyExists
                }
                guard let destination = agentSkillsStore.skillDirectoryURL(agentID: normalizedAgentID, skillID: skillID) else {
                    throw AgentSkillsError.storageFailure
                }
                downloadedSkill = try await skillsGitHubClient.installLocalSkill(
                    sourcePath: localPath,
                    destination: destination,
                    owner: owner.isEmpty ? nil : owner,
                    repo: localRepo
                )
            } else {
                let skillID = "\(owner)/\(repo)"
                if existingSkills.contains(where: { $0.id == skillID }) {
                    throw AgentSkillsError.skillAlreadyExists
                }
                guard let destination = agentSkillsStore.skillDirectoryURL(agentID: normalizedAgentID, skillID: skillID) else {
                    throw AgentSkillsError.storageFailure
                }
                downloadedSkill = try await skillsGitHubClient.downloadSkill(
                    owner: owner,
                    repo: repo,
                    version: request.version,
                    destination: destination
                )
            }

            let fm = downloadedSkill.frontmatter
            let userInvocable = request.userInvocable ?? fm?.userInvocable ?? true
            let allowedTools = request.allowedTools ?? fm?.allowedTools ?? []
            let contextValue: SkillContext? = request.context ?? {
                if let raw = fm?.context, raw.lowercased() == "fork" { return .fork }
                return nil
            }()
            let agentValue = request.agent ?? fm?.agent
            let autoRouteValue = request.autoRoute ?? fm?.autoRoute

            let installedSkill = try agentSkillsStore.installSkill(
                agentID: normalizedAgentID,
                owner: downloadedSkill.owner,
                repo: downloadedSkill.repo,
                name: downloadedSkill.name,
                description: downloadedSkill.description,
                userInvocable: userInvocable,
                allowedTools: allowedTools,
                context: contextValue,
                agent: agentValue,
                autoRoute: autoRouteValue,
                localPath: downloadedSkill.localPath
            )

            await sessionOrchestrator.notifySkillsChanged(agentID: normalizedAgentID)

            return installedSkill
        } catch let error as AgentSkillsFileStore.StoreError {
            throw mapAgentSkillsError(error)
        } catch let clientError as SkillsGitHubClient.ClientError {
            logger.error(
                installingLocalSkill ? "skills.install.local_failed" : "skills.install.download_failed",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "owner": .string(owner.isEmpty ? "local" : owner),
                    "repo": .string(repo.isEmpty ? (localPath.map { Self.defaultLocalSkillRepo(from: $0) } ?? "") : repo),
                    "skill_error": .string(clientError.logDescription)
                ]
            )
            throw installingLocalSkill ? AgentSkillsError.localPathFailure : AgentSkillsError.downloadFailure
        } catch {
            logger.error(
                "skills.install.unexpected_error",
                metadata: [
                    "agent_id": .string(normalizedAgentID),
                    "owner": .string(owner),
                    "repo": .string(repo),
                    "error": .string(String(describing: error))
                ]
            )
            throw AgentSkillsError.storageFailure
        }
    }

    private static func defaultLocalSkillRepo(from localPath: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: localPath).standardizedFileURL.lastPathComponent
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        var result = String(lastPathComponent.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "skill" : result
    }


    /// Uninstall a skill from an agent
    public func uninstallAgentSkill(agentID: String, skillID: String) async throws {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)

        do {
            try agentSkillsStore.uninstallSkill(agentID: normalizedAgentID, skillID: skillID)
        } catch let error as AgentSkillsFileStore.StoreError {
            throw mapAgentSkillsError(error)
        } catch {
            throw AgentSkillsError.storageFailure
        }

        await sessionOrchestrator.notifySkillsChanged(agentID: normalizedAgentID)
    }

    /// Get agent skills for runtime use
    public func getAgentSkillsForRuntime(agentID: String) async throws -> [InstalledSkill] {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)

        do {
            try agentSkillsStore.provisionBuiltInSkills(agentID: normalizedAgentID)
            return try agentSkillsStore.listSkills(agentID: normalizedAgentID)
        } catch {
            return []
        }
    }

    /// Ensure skills directory exists (called during agent creation)
    public func ensureAgentSkillsDirectory(agentID: String) async throws {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }

        do {
            try agentSkillsStore.ensureSkillsDirectory(agentID: normalizedAgentID)
        } catch {
            throw AgentSkillsError.storageFailure
        }
    }

    func mapAgentSkillsError(_ error: AgentSkillsFileStore.StoreError) -> AgentSkillsError {
        switch error {
        case .invalidAgentID:
            return .invalidAgentID
        case .agentNotFound:
            return .agentNotFound
        case .skillAlreadyExists:
            return .skillAlreadyExists
        case .skillNotFound:
            return .skillNotFound
        default:
            return .storageFailure
        }
    }

    /// Channel plugin slash commands plus user-invocable skill shortcuts for agent chat UI (Dashboard).
    public func buildAgentChatSlashCommands(agentID: String) async throws -> AgentChatSlashCommandsResponse {
        guard let normalizedAgentID = normalizedAgentID(agentID) else {
            throw AgentSkillsError.invalidAgentID
        }
        _ = try getAgent(id: normalizedAgentID)

        var items: [AgentChatSlashCommandItem] = []
        for cmd in ChannelCommandHandler.commands(for: .dashboard) {
            items.append(
                AgentChatSlashCommandItem(
                    source: "channel",
                    name: cmd.name,
                    description: cmd.description,
                    argument: cmd.argument,
                    skillId: nil
                )
            )
        }
        let builtin = Set(ChannelCommandHandler.allCommands.map { $0.name.lowercased() })
        let skills = try await getAgentSkillsForRuntime(agentID: normalizedAgentID)
        let invocableSkills = skills.filter(\.userInvocable)
        let resolvedTokens = SkillSlashCommandNaming.resolvedSlashTokens(
            forSkillIds: invocableSkills.map(\.id),
            reservedTokens: builtin
        )
        for skill in invocableSkills {
            let token = resolvedTokens[skill.id] ?? SkillSlashCommandNaming.slashToken(fromSkillId: skill.repo)
            let repoToken = SkillSlashCommandNaming.slashToken(fromSkillId: skill.repo)
            items.append(
                AgentChatSlashCommandItem(
                    source: "skill",
                    name: token,
                    description: Self.skillSlashDescription(for: skill),
                    argument: nil,
                    skillId: skill.id,
                    displayName: skill.name,
                    owner: skill.owner,
                    repo: skill.repo,
                    disambiguated: token != repoToken
                )
            )
        }
        items.sort { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source < rhs.source
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return AgentChatSlashCommandsResponse(commands: items)
    }

    static func skillSlashDescription(for skill: InstalledSkill) -> String {
        let suffix = " [\(skill.id)]"
        if let d = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            return "\(skill.name) — \(d)\(suffix)"
        }
        return "\(skill.name)\(suffix)"
    }
}

// MARK: - Event cursor utilities

extension CoreService {
    static func encodeEventCursor(_ event: EventEnvelope) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(formatter.string(from: event.ts))|\(event.messageId)"
    }

    static func decodeEventCursor(_ rawValue: String?) -> PersistedEventCursor? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        let parts = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let timestamp = String(parts[0])
        let eventID = String(parts[1])
        guard !eventID.isEmpty else {
            return nil
        }
        guard let createdAt = decodeEventCursorDate(timestamp) else {
            return nil
        }

        return PersistedEventCursor(createdAt: createdAt, eventId: eventID)
    }

    static func decodeEventCursorDate(_ value: String) -> Date? {
        let formatterWithFractions = ISO8601DateFormatter()
        formatterWithFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatterWithFractions.date(from: value) {
            return parsed
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }
}
