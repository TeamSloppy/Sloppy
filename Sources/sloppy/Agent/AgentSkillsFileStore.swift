import Foundation
import Protocols

/// Manages storage of skills for agents in the file system.
/// Skills are stored in /workspace/agents/AGENT_ID/skills/
final class AgentSkillsFileStore {
    enum StoreError: Error {
        case invalidAgentID
        case agentNotFound
        case skillAlreadyExists
        case skillNotFound
        case storageFailure
        case manifestReadFailed
        case manifestWriteFailed
        case invalidSkillID
    }

    private let fileManager: FileManager
    private var agentsRootURL: URL
    private let sharedSkillsRootURLs: [URL]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        agentsRootURL: URL,
        sharedSkillsRootURLs: [URL] = AgentSkillsFileStore.defaultSharedSkillsRootURLs,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.agentsRootURL = agentsRootURL
        self.sharedSkillsRootURLs = sharedSkillsRootURLs.map(\.standardizedFileURL)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func updateAgentsRootURL(_ url: URL) {
        self.agentsRootURL = url
    }

    func sharedSkillsRootPaths() -> [String] {
        sharedSkillsRootURLs
            .map { $0.appendingPathComponent("skills", isDirectory: true).standardizedFileURL.path }
    }

    // MARK: - Directory Paths

    private func resolvedAgentDirectoryURL(agentID: String) -> URL? {
        let regular = agentsRootURL.appendingPathComponent(agentID, isDirectory: true)
        if fileManager.fileExists(atPath: regular.path) {
            return regular
        }
        let system = agentsRootURL.appendingPathComponent(".system", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
        if fileManager.fileExists(atPath: system.path) {
            return system
        }
        return nil
    }

    func skillsDirectoryURL(agentID: String) -> URL? {
        resolvedAgentDirectoryURL(agentID: agentID)?
            .appendingPathComponent("skills", isDirectory: true)
    }

    func skillDirectoryURL(agentID: String, skillID: String) -> URL? {
        skillsDirectoryURL(agentID: agentID)?
            .appendingPathComponent(skillID, isDirectory: true)
    }

    func manifestURL(agentID: String) -> URL? {
        skillsDirectoryURL(agentID: agentID)?
            .appendingPathComponent("skills.json")
    }

    // MARK: - Manifest Management

    func readManifest(agentID: String) throws -> AgentSkillsManifest {
        guard let url = manifestURL(agentID: agentID) else {
            return AgentSkillsManifest()
        }

        guard fileManager.fileExists(atPath: url.path) else {
            return AgentSkillsManifest()
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AgentSkillsManifest.self, from: data)
        } catch {
            throw StoreError.manifestReadFailed
        }
    }

    func writeManifest(_ manifest: AgentSkillsManifest, agentID: String) throws {
        guard let directory = skillsDirectoryURL(agentID: agentID) else {
            throw StoreError.agentNotFound
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let url = manifestURL(agentID: agentID) else {
            throw StoreError.agentNotFound
        }
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Skills Operations

    /// List all installed skills for an agent
    func listSkills(agentID: String) throws -> [InstalledSkill] {
        let normalizedAgentID = try normalizedAgentID(agentID)

        guard resolvedAgentDirectoryURL(agentID: normalizedAgentID) != nil else {
            throw StoreError.agentNotFound
        }

        let manifest = try readManifest(agentID: normalizedAgentID)
        return mergeInstalledSkills(manifest.installedSkills, with: sharedSkills())
    }

    /// Get a specific skill by ID
    func getSkill(agentID: String, skillID: String) throws -> InstalledSkill {
        let normalizedAgentID = try normalizedAgentID(agentID)
        let normalizedSkillID = try normalizedSkillID(skillID)

        let manifest = try readManifest(agentID: normalizedAgentID)

        guard let skill = manifest.installedSkills.first(where: { $0.id == normalizedSkillID }) ??
                sharedSkills().first(where: { $0.id == normalizedSkillID })
        else {
            throw StoreError.skillNotFound
        }

        return skill
    }

    /// Install a new skill for an agent
    @discardableResult
    func installSkill(
        agentID: String,
        owner: String,
        repo: String,
        name: String,
        description: String?,
        userInvocable: Bool = true,
        allowedTools: [String] = [],
        context: SkillContext? = nil,
        agent: String? = nil,
        localPath: String? = nil
    ) throws -> InstalledSkill {
        let normalizedAgentID = try normalizedAgentID(agentID)

        guard resolvedAgentDirectoryURL(agentID: normalizedAgentID) != nil else {
            throw StoreError.agentNotFound
        }

        let skillID = "\(owner)/\(repo)"
        guard let skillDirectory = skillDirectoryURL(agentID: normalizedAgentID, skillID: skillID) else {
            throw StoreError.agentNotFound
        }

        var manifest = try readManifest(agentID: normalizedAgentID)
        if manifest.installedSkills.contains(where: { $0.id == skillID }) {
            throw StoreError.skillAlreadyExists
        }

        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let storedLocalPath: String
        if let localPath = localPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localPath.isEmpty {
            let standardizedSkillDirectory = skillDirectory.standardizedFileURL.path
            let standardizedLocalPath = URL(fileURLWithPath: localPath).standardizedFileURL.path
            guard standardizedLocalPath == standardizedSkillDirectory ||
                  standardizedLocalPath.hasPrefix(standardizedSkillDirectory + "/")
            else {
                throw StoreError.storageFailure
            }
            storedLocalPath = standardizedLocalPath
        } else {
            storedLocalPath = skillDirectory.path
        }

        let skill = InstalledSkill(
            id: skillID,
            owner: owner,
            repo: repo,
            name: name,
            description: description,
            localPath: storedLocalPath,
            userInvocable: userInvocable,
            allowedTools: allowedTools,
            context: context,
            agent: agent
        )

        manifest.installedSkills.append(skill)
        try writeManifest(manifest, agentID: normalizedAgentID)

        return skill
    }

    /// Uninstall a skill from an agent
    func uninstallSkill(agentID: String, skillID: String) throws {
        let normalizedAgentID = try normalizedAgentID(agentID)
        let normalizedSkillID = try normalizedSkillID(skillID)

        var manifest = try readManifest(agentID: normalizedAgentID)
        guard let index = manifest.installedSkills.firstIndex(where: { $0.id == normalizedSkillID }) else {
            throw StoreError.skillNotFound
        }

        if let skillDirectory = skillDirectoryURL(agentID: normalizedAgentID, skillID: normalizedSkillID),
           fileManager.fileExists(atPath: skillDirectory.path) {
            try fileManager.removeItem(at: skillDirectory)
        }

        manifest.installedSkills.remove(at: index)
        try writeManifest(manifest, agentID: normalizedAgentID)
    }

    /// Get the path to a skill directory for external file operations
    func getSkillPath(agentID: String, skillID: String) throws -> String {
        let normalizedAgentID = try normalizedAgentID(agentID)
        let normalizedSkillID = try normalizedSkillID(skillID)

        if let skill = try? getSkill(agentID: normalizedAgentID, skillID: normalizedSkillID) {
            let localPath = skill.localPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !localPath.isEmpty {
                return localPath
            }
        }

        guard let skillDirectory = skillDirectoryURL(agentID: normalizedAgentID, skillID: normalizedSkillID) else {
            throw StoreError.agentNotFound
        }
        return skillDirectory.path
    }

    /// Ensure skills directory exists for an agent (called during agent creation)
    func ensureSkillsDirectory(agentID: String) throws {
        let normalizedAgentID = try normalizedAgentID(agentID)
        guard let directory = skillsDirectoryURL(agentID: normalizedAgentID) else {
            throw StoreError.agentNotFound
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let manifestPath = manifestURL(agentID: normalizedAgentID) else {
            throw StoreError.agentNotFound
        }
        if !fileManager.fileExists(atPath: manifestPath.path) {
            let manifest = AgentSkillsManifest()
            try writeManifest(manifest, agentID: normalizedAgentID)
        }
        try provisionBuiltInSkills(agentID: normalizedAgentID)
    }

    @discardableResult
    func provisionBuiltInSkills(agentID: String) throws -> [InstalledSkill] {
        try BuiltInSkillCatalog.all().map { definition in
            try provisionBuiltInSkill(agentID: agentID, definition: definition)
        }
    }

    @discardableResult
    private func provisionBuiltInSkill(
        agentID: String,
        definition: BuiltInSkillDefinition
    ) throws -> InstalledSkill {
        let normalizedAgentID = try normalizedAgentID(agentID)
        guard resolvedAgentDirectoryURL(agentID: normalizedAgentID) != nil else {
            throw StoreError.agentNotFound
        }

        let skillID = "\(definition.owner)/\(definition.repo)"
        _ = try normalizedSkillID(skillID)
        guard let skillDirectory = skillDirectoryURL(agentID: normalizedAgentID, skillID: skillID) else {
            throw StoreError.agentNotFound
        }

        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        for (relativePath, content) in definition.files {
            let destination = try safeSkillFileURL(relativePath: relativePath, skillDirectory: skillDirectory)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(content.utf8).write(to: destination, options: .atomic)
        }

        var manifest = try readManifest(agentID: normalizedAgentID)
        let installed: InstalledSkill
        if let index = manifest.installedSkills.firstIndex(where: { $0.id == skillID }) {
            let existing = manifest.installedSkills[index]
            installed = InstalledSkill(
                id: skillID,
                owner: definition.owner,
                repo: definition.repo,
                name: definition.name,
                description: definition.description,
                installedAt: existing.installedAt,
                version: existing.version ?? "built-in",
                localPath: skillDirectory.standardizedFileURL.path,
                userInvocable: definition.userInvocable,
                allowedTools: definition.allowedTools,
                context: existing.context,
                agent: existing.agent
            )
            manifest.installedSkills[index] = installed
        } else {
            installed = InstalledSkill(
                id: skillID,
                owner: definition.owner,
                repo: definition.repo,
                name: definition.name,
                description: definition.description,
                version: "built-in",
                localPath: skillDirectory.standardizedFileURL.path,
                userInvocable: definition.userInvocable,
                allowedTools: definition.allowedTools
            )
            manifest.installedSkills.append(installed)
        }

        try writeManifest(manifest, agentID: normalizedAgentID)
        return installed
    }

    private func safeSkillFileURL(relativePath: String, skillDirectory: URL) throws -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw StoreError.invalidSkillID
        }

        let destination = components.reduce(skillDirectory.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(component)
        }.standardizedFileURL
        let root = skillDirectory.standardizedFileURL.path
        guard destination.path == root || destination.path.hasPrefix(root + "/") else {
            throw StoreError.invalidSkillID
        }
        return destination
    }

    // MARK: - Shared Skills

    private static var defaultSharedSkillsRootURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".agents", isDirectory: true)]
    }

    private func sharedSkills() -> [InstalledSkill] {
        var skillsByID: [String: InstalledSkill] = [:]
        for root in sharedSkillsRootURLs {
            for skill in sharedSkills(in: root) {
                if skillsByID[skill.id] == nil {
                    skillsByID[skill.id] = skill
                }
            }
        }
        return skillsByID.values.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    private func sharedSkills(in root: URL) -> [InstalledSkill] {
        let skillsRoot = root.appendingPathComponent("skills", isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: skillsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let children = try? fileManager.contentsOfDirectory(
                at: skillsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return children.compactMap { child -> InstalledSkill? in
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else {
                return nil
            }
            return sharedSkill(from: child.standardizedFileURL)
        }
    }

    private func sharedSkill(from directory: URL) -> InstalledSkill? {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: skillFile.path),
              let markdown = try? String(contentsOf: skillFile, encoding: .utf8)
        else {
            return nil
        }

        let repo = skillIDComponent(from: directory.lastPathComponent)
        let id = "shared/\(repo)"
        let frontmatter = SkillsGitHubClient.parseFrontmatter(from: markdown)
        let name = normalizedFrontmatterValue(frontmatter?.name) ?? repo
        let description = normalizedFrontmatterValue(frontmatter?.description)
        let userInvocable = frontmatter?.userInvocable ?? true
        let allowedTools = frontmatter?.allowedTools ?? []
        let context: SkillContext? = {
            guard let raw = normalizedFrontmatterValue(frontmatter?.context) else {
                return nil
            }
            return SkillContext(rawValue: raw)
        }()

        return InstalledSkill(
            id: id,
            owner: "shared",
            repo: repo,
            name: name,
            description: description,
            version: "shared",
            localPath: directory.standardizedFileURL.path,
            userInvocable: userInvocable,
            allowedTools: allowedTools,
            context: context,
            agent: normalizedFrontmatterValue(frontmatter?.agent)
        )
    }

    private func mergeInstalledSkills(_ primary: [InstalledSkill], with shared: [InstalledSkill]) -> [InstalledSkill] {
        var merged = primary
        var existingIDs = Set(primary.map(\.id))
        for skill in shared where !existingIDs.contains(skill.id) {
            merged.append(skill)
            existingIDs.insert(skill.id)
        }
        return merged
    }

    private func normalizedFrontmatterValue(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func skillIDComponent(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        var result = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "skill" : result
    }

    // MARK: - Validation

    private func normalizedAgentID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.invalidAgentID
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw StoreError.invalidAgentID
        }
        return trimmed
    }

    private func normalizedSkillID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.invalidSkillID
        }
        // Allow owner/repo format with alphanumeric, hyphens, underscores
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.-/")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw StoreError.invalidSkillID
        }
        return trimmed
    }
}
