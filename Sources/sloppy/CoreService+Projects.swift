import Foundation
import AppKit
import AgentRuntime
import Protocols
import Logging

// MARK: - Projects

extension CoreService {
    public func listProjects() async -> [ProjectRecord] {
        await store.listProjects()
    }

    /// Lists token usage records with optional filters and aggregates.
    public func listTokenUsage(
        channelId: String? = nil,
        taskId: String? = nil,
        from: Date? = nil,
        to: Date? = nil
    ) async -> TokenUsageResponse {
        let records = await store.listTokenUsage(channelId: channelId, taskId: taskId, from: from, to: to)
        let totalPrompt = records.reduce(0) { $0 + $1.promptTokens }
        let totalCompletion = records.reduce(0) { $0 + $1.completionTokens }
        let total = records.reduce(0) { $0 + $1.totalTokens }
        return TokenUsageResponse(
            items: records,
            totalPromptTokens: totalPrompt,
            totalCompletionTokens: totalCompletion,
            totalTokens: total
        )
    }

    /// Lists runtime event timeline for a channel (newest first) with cursor pagination.
    public func getProject(id: String) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(id) else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }
        return project
    }

    public func listProjectFiles(projectID: String, path: String) async throws -> [ProjectFileEntry] {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        let rootPath = project.repoPath ?? projectDirectoryURL(projectID: normalizedID).path
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardized

        let targetURL: URL
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty || trimmedPath == "/" {
            targetURL = rootURL
        } else {
            targetURL = rootURL.appendingPathComponent(trimmedPath).standardized
        }

        guard targetURL.path.hasPrefix(rootURL.path) else {
            throw ProjectError.invalidProjectID
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectError.notFound
        }

        let contents = try fm.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var entries: [ProjectFileEntry] = []
        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize
            entries.append(ProjectFileEntry(
                name: url.lastPathComponent,
                type: isDirectory ? .directory : .file,
                size: isDirectory ? nil : size
            ))
        }
        entries.sort {
            if $0.type == $1.type { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.type == .directory
        }
        return entries
    }

    public func readProjectFile(projectID: String, path: String) async throws -> ProjectFileContentResponse {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        let rootPath = project.repoPath ?? projectDirectoryURL(projectID: normalizedID).path
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardized

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw ProjectError.invalidProjectID
        }

        let targetURL = rootURL.appendingPathComponent(trimmedPath).standardized
        guard targetURL.path.hasPrefix(rootURL.path) else {
            throw ProjectError.invalidProjectID
        }

        let maxBytes = 2 * 1024 * 1024
        let data = try Data(contentsOf: targetURL)
        guard data.count <= maxBytes else {
            throw ProjectError.invalidProjectID
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProjectError.invalidProjectID
        }

        let relativePath = String(targetURL.path.dropFirst(rootURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ProjectFileContentResponse(path: relativePath, content: text, sizeBytes: data.count)
    }

    /// Creates a new dashboard project.
    public func createProject(_ request: ProjectCreateRequest) async throws -> ProjectRecord {
        let now = Date()
        let normalizedName = try normalizeProjectName(request.name)
        let normalizedDescription = normalizeProjectDescription(request.description)
        let trimmedRepoUrl = request.repoUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasRepoUrl = !trimmedRepoUrl.isEmpty
        let normalizedRepoPath = try normalizedExternalProjectPath(request.repoPath)

        if hasRepoUrl, normalizedRepoPath != nil {
            throw ProjectError.invalidPayload
        }
        let normalizedID: String
        if let requestedID = request.id, !requestedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let validID = normalizedProjectID(requestedID) else {
                throw ProjectError.invalidProjectID
            }
            guard await store.project(id: validID) == nil else {
                throw ProjectError.conflict
            }
            normalizedID = validID
        } else {
            normalizedID = UUID().uuidString
        }
        let channels = try normalizeInitialProjectChannels(request.channels, fallbackName: normalizedName)
        let project = ProjectRecord(
            id: normalizedID,
            name: normalizedName,
            description: normalizedDescription,
            channels: channels,
            tasks: [],
            actors: request.actors ?? [],
            teams: request.teams ?? [],
            repoPath: normalizedRepoPath,
            createdAt: now,
            updatedAt: now
        )

        if let normalizedRepoPath {
            try prepareExternalProjectWorkspace(projectID: normalizedID, repoPath: normalizedRepoPath)
        }

        await store.saveProject(project)
        if hasRepoUrl {
            await cloneProjectRepository(repoUrl: trimmedRepoUrl, projectID: normalizedID)
        } else {
            ensureProjectWorkspaceDirectory(projectID: normalizedID)
        }
        if !currentConfig.onboarding.completed {
            logger.info(
                "onboarding.project.created",
                metadata: [
                    "project_id": .string(normalizedID),
                    "project_name": .string(normalizedName)
                ]
            )
        }
        return project
    }

    public func selectDirectory() async -> String? {
#if canImport(AppKit)
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                NSApplication.shared.activate(ignoringOtherApps: true)

                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.title = "Choose Project Directory"
                panel.prompt = "Open Project"

                func finish(_ response: NSApplication.ModalResponse) {
                    guard response == .OK else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: panel.url?.path)
                }

                if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
                    panel.beginSheetModal(for: window, completionHandler: finish)
                } else {
                    finish(panel.runModal())
                }
            }
        }
#else
        return nil
#endif
    }

    /// Updates dashboard project metadata.
    public func updateProject(projectID: String, request: ProjectUpdateRequest) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        if let nextName = request.name {
            project.name = try normalizeProjectName(nextName)
        }
        if let nextDescription = request.description {
            project.description = normalizeProjectDescription(nextDescription)
        }
        if request.icon != nil {
            project.icon = request.icon
        }
        if let nextActors = request.actors {
            project.actors = nextActors
        }
        if let nextTeams = request.teams {
            project.teams = nextTeams
        }
        if let nextModels = request.models {
            project.models = nextModels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let nextAgentFiles = request.agentFiles {
            project.agentFiles = nextAgentFiles.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let nextHeartbeat = request.heartbeat {
            project.heartbeat = nextHeartbeat
        }
        if request.repoPath != nil {
            project.repoPath = request.repoPath
        }
        if let nextReviewSettings = request.reviewSettings {
            project.reviewSettings = nextReviewSettings
        }
        if let nextLoopMode = request.taskLoopMode {
            project.taskLoopMode = nextLoopMode
        }
        if let nextArchived = request.isArchived {
            project.isArchived = nextArchived
        }

        project.updatedAt = Date()
        await store.saveProject(project)
        return project
    }

    /// Deletes one dashboard project and nested board entities.
    /// Cancels all non-terminal tasks before deletion.
    public func deleteProject(projectID: String) async throws {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }
        for i in project.tasks.indices {
            let status = ProjectTaskStatus(rawValue: project.tasks[i].status)
            if status == nil || !status!.isTerminal {
                project.tasks[i].status = ProjectTaskStatus.cancelled.rawValue
                project.tasks[i].updatedAt = Date()
            }
        }
        project.updatedAt = Date()
        await store.saveProject(project)
        await store.deleteProject(id: normalizedID)
    }

    /// Adds a channel to a dashboard project.
    public func createProjectChannel(
        projectID: String,
        request: ProjectChannelCreateRequest
    ) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        let title = normalizeChannelTitle(request.title)
        let channelID = try normalizedChannelID(request.channelId)
        if project.channels.contains(where: { $0.channelId == channelID }) {
            throw ProjectError.conflict
        }

        project.channels.append(
            ProjectChannel(
                id: UUID().uuidString,
                title: title,
                channelId: channelID,
                createdAt: Date()
            )
        )
        project.updatedAt = Date()
        await store.saveProject(project)
        return project
    }

    /// Removes a channel from a dashboard project.
    public func deleteProjectChannel(projectID: String, channelID: String) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedChannel = normalizedEntityID(channelID) else {
            throw ProjectError.invalidChannelID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        guard project.channels.contains(where: { $0.id == normalizedChannel }) else {
            throw ProjectError.notFound
        }
        if project.channels.count <= 1 {
            throw ProjectError.invalidPayload
        }

        project.channels.removeAll(where: { $0.id == normalizedChannel })
        project.updatedAt = Date()
        await store.saveProject(project)
        return project
    }

    /// Creates a new task inside project board.
    public func createProjectTask(projectID: String, request: ProjectTaskCreateRequest) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        let now = Date()
        let rawStatus = request.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let resolvedStatus = ProjectTaskStatus(rawValue: rawStatus) != nil ? rawStatus : ProjectTaskStatus.backlog.rawValue
        let normalizedStatus = try normalizeTaskStatus(resolvedStatus)
        let task = ProjectTask(
            id: nextProjectTaskID(for: project),
            title: try normalizeTaskTitle(request.title),
            description: normalizeTaskDescription(request.description),
            priority: try normalizeTaskPriority(request.priority),
            status: normalizedStatus,
            kind: request.kind,
            loopModeOverride: request.loopModeOverride,
            originType: request.originType,
            originChannelId: request.originChannelId,
            actorId: try normalizeOptionalTaskActorID(request.actorId),
            teamId: try normalizeOptionalTaskTeamID(request.teamId),
            createdAt: now,
            updatedAt: now
        )
        project.tasks.append(task)
        project.updatedAt = now
        await store.saveProject(project)
        if normalizedStatus == ProjectTaskStatus.ready.rawValue {
            await handleTaskBecameReady(projectID: normalizedID, taskID: task.id)
            if let updated = await store.project(id: normalizedID) {
                return updated
            }
        }
        return project
    }

    /// Updates one task inside project board.
    public func updateProjectTask(
        projectID: String,
        taskID: String,
        request: ProjectTaskUpdateRequest
    ) async throws -> ProjectRecord {
        guard let normalizedProject = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedTask = normalizedEntityID(taskID) else {
            throw ProjectError.invalidTaskID
        }
        let normalizedTaskLowercased = normalizedTask.lowercased()
        guard var project = await store.project(id: normalizedProject) else {
            throw ProjectError.notFound
        }
        guard let taskIndex = project.tasks.firstIndex(where: { $0.id.lowercased() == normalizedTaskLowercased }) else {
            throw ProjectError.notFound
        }

        let previousStatus = project.tasks[taskIndex].status
        let oldTask = project.tasks[taskIndex]
        var task = oldTask
        if let title = request.title {
            task.title = try normalizeTaskTitle(title)
        }
        if let description = request.description {
            task.description = normalizeTaskDescription(description)
        }
        if let priority = request.priority {
            task.priority = try normalizeTaskPriority(priority)
        }
        if request.actorId != nil {
            task.actorId = try normalizeOptionalTaskActorID(request.actorId)
            task.claimedActorId = nil
            task.claimedAgentId = nil
        }
        if request.teamId != nil {
            task.teamId = try normalizeOptionalTaskTeamID(request.teamId)
            task.claimedActorId = nil
            task.claimedAgentId = nil
        }
        if let kind = request.kind {
            task.kind = kind
        }
        if request.loopModeOverride != nil {
            task.loopModeOverride = request.loopModeOverride
        }
        if let status = request.status {
            task.status = try normalizeTaskStatus(status)
            if task.status == ProjectTaskStatus.backlog.rawValue || task.status == ProjectTaskStatus.cancelled.rawValue {
                task.claimedActorId = nil
                task.claimedAgentId = nil
            }
        }
        task.updatedAt = Date()
        project.tasks[taskIndex] = task
        project.updatedAt = Date()
        await store.saveProject(project)

        let changedBy = request.changedBy ?? "user"
        await recordTaskFieldChanges(
            projectID: normalizedProject,
            taskID: task.id,
            oldTask: oldTask,
            newTask: task,
            changedBy: changedBy
        )

        let actorChanged = request.actorId != nil && oldTask.actorId != task.actorId
        let teamChanged = request.teamId != nil && oldTask.teamId != task.teamId
        let assigneeChangedWhileReady = (actorChanged || teamChanged)
            && task.status == ProjectTaskStatus.ready.rawValue

        if previousStatus != ProjectTaskStatus.ready.rawValue, task.status == ProjectTaskStatus.ready.rawValue {
            await handleTaskBecameReady(projectID: normalizedProject, taskID: task.id)
            if let updated = await store.project(id: normalizedProject) {
                return updated
            }
        } else if assigneeChangedWhileReady {
            await handleTaskBecameReady(projectID: normalizedProject, taskID: task.id)
            if let updated = await store.project(id: normalizedProject) {
                return updated
            }
        }
        return project
    }

    /// Removes one task from project board.
    public func deleteProjectTask(projectID: String, taskID: String) async throws -> ProjectRecord {
        guard let normalizedProject = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard let normalizedTask = normalizedEntityID(taskID) else {
            throw ProjectError.invalidTaskID
        }
        let normalizedTaskLowercased = normalizedTask.lowercased()
        guard var project = await store.project(id: normalizedProject) else {
            throw ProjectError.notFound
        }
        guard project.tasks.contains(where: { $0.id.lowercased() == normalizedTaskLowercased }) else {
            throw ProjectError.notFound
        }

        project.tasks.removeAll(where: { $0.id.lowercased() == normalizedTaskLowercased })
        project.updatedAt = Date()
        await store.saveProject(project)
        return project
    }

    private static let taskArchiveThreshold: TimeInterval = 2 * 24 * 60 * 60

    private static let archivableStatuses: Set<String> = [
        ProjectTaskStatus.done.rawValue,
        ProjectTaskStatus.cancelled.rawValue
    ]

    @discardableResult
    public func archiveOldTasks(projectID: String) async throws -> ProjectRecord {
        guard let normalizedID = normalizedProjectID(projectID) else {
            throw ProjectError.invalidProjectID
        }
        guard var project = await store.project(id: normalizedID) else {
            throw ProjectError.notFound
        }

        let cutoff = Date().addingTimeInterval(-Self.taskArchiveThreshold)
        var changed = false
        for index in project.tasks.indices {
            let task = project.tasks[index]
            if !task.isArchived,
               Self.archivableStatuses.contains(task.status),
               task.updatedAt < cutoff {
                project.tasks[index].isArchived = true
                changed = true
            }
        }

        if changed {
            project.updatedAt = Date()
            await store.saveProject(project)
        }
        return project
    }

    public func listArchivedTasks(projectID: String) async throws -> [ProjectTask] {
        let project = try await archiveOldTasks(projectID: projectID)
        return project.tasks.filter(\.isArchived)
    }

    /// Returns one task by readable id (for example, `MOBILE-1`).
    public func getProjectTask(taskReference: String) async throws -> AgentTaskRecord {
        guard let normalizedReference = normalizeTaskReference(taskReference) else {
            throw ProjectError.invalidTaskID
        }
        let normalizedReferenceLowercased = normalizedReference.lowercased()

        let projects = await store.listProjects().sorted(by: { $0.createdAt < $1.createdAt })
        for project in projects {
            guard let task = project.tasks.first(where: { $0.id.lowercased() == normalizedReferenceLowercased }) else {
                continue
            }

            return AgentTaskRecord(
                projectId: project.id,
                projectName: project.name,
                task: task
            )
        }

        throw ProjectError.notFound
    }

    func normalizeProjectName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 160 else {
            throw ProjectError.invalidPayload
        }
        return trimmed
    }

    func normalizeProjectDescription(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(2_000))
    }

    func normalizeInitialProjectChannels(
        _ channels: [ProjectChannelCreateRequest],
        fallbackName: String
    ) throws -> [ProjectChannel] {
        if channels.isEmpty {
            let slug = slugify(fallbackName)
            return [
                ProjectChannel(
                    id: UUID().uuidString,
                    title: "Main channel",
                    channelId: slug.isEmpty ? "project-main" : "\(slug)-main",
                    createdAt: Date()
                )
            ]
        }

        var normalized: [ProjectChannel] = []
        var uniqueChannelIDs: Set<String> = []
        for channel in channels {
            let title = normalizeChannelTitle(channel.title)
            let channelID = try normalizedChannelID(channel.channelId)
            guard uniqueChannelIDs.insert(channelID).inserted else {
                throw ProjectError.conflict
            }
            normalized.append(
                ProjectChannel(
                    id: UUID().uuidString,
                    title: title,
                    channelId: channelID,
                    createdAt: Date()
                )
            )
        }
        return normalized
    }

    func normalizeTaskTitle(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectError.invalidPayload
        }
        return String(trimmed.prefix(240))
    }

    func normalizeTaskDescription(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(8_000))
    }

    func normalizeTaskPriority(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = Set(["low", "medium", "high"])
        guard allowed.contains(value) else {
            throw ProjectError.invalidPayload
        }
        return value
    }

    func normalizeTaskStatus(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = Set(ProjectTaskStatus.allCases.map(\.rawValue))
        guard allowed.contains(value) else {
            throw ProjectError.invalidPayload
        }
        return value
    }

    func normalizeOptionalTaskActorID(_ raw: String?) throws -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let normalized = normalizedActorEntityID(trimmed) else {
            throw ProjectError.invalidPayload
        }
        return normalized
    }

    func normalizeOptionalTaskTeamID(_ raw: String?) throws -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let normalized = normalizedActorEntityID(trimmed) else {
            throw ProjectError.invalidPayload
        }
        return normalized
    }

    func normalizeTaskReference(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let token = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        return normalizedEntityID(token)
    }

    func nextProjectTaskID(for project: ProjectRecord) -> String {
        let prefix = projectTaskIDPrefix(for: project)
        let taskPrefix = "\(prefix)-"
        let maxSequence = project.tasks.reduce(0) { partial, task in
            max(partial, taskSequenceNumber(taskID: task.id, prefix: taskPrefix) ?? 0)
        }
        return "\(prefix)-\(maxSequence + 1)"
    }

    func projectTaskIDPrefix(for project: ProjectRecord) -> String {
        var candidates: [String] = []
        if !isLikelyUUID(project.id) {
            candidates.append(project.id)
        }
        candidates.append(project.name)
        if isLikelyUUID(project.id) {
            candidates.append(project.id)
        }

        for candidate in candidates {
            let normalized = normalizeTaskPrefix(candidate)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return "PROJECT"
    }

    func taskSequenceNumber(taskID: String, prefix: String) -> Int? {
        let uppercased = taskID.uppercased()
        guard uppercased.hasPrefix(prefix) else {
            return nil
        }

        let suffix = String(uppercased.dropFirst(prefix.count))
        guard !suffix.isEmpty,
              suffix.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
        else {
            return nil
        }
        return Int(suffix)
    }

    func normalizeTaskPrefix(_ raw: String) -> String {
        let uppercased = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !uppercased.isEmpty else {
            return ""
        }

        let compacted = uppercased.replacingOccurrences(
            of: #"[^A-Z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = compacted.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(80))
    }

    func isLikelyUUID(_ raw: String) -> Bool {
        raw.range(
            of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    func jsonValue(for task: ProjectTask) -> JSONValue {
        .object([
            "id": .string(task.id),
            "title": .string(task.title),
            "description": .string(task.description),
            "priority": .string(task.priority),
            "status": .string(task.status),
            "actorId": task.actorId.map { .string($0) } ?? .null,
            "teamId": task.teamId.map { .string($0) } ?? .null,
            "claimedActorId": task.claimedActorId.map { .string($0) } ?? .null,
            "claimedAgentId": task.claimedAgentId.map { .string($0) } ?? .null,
            "swarmId": task.swarmId.map { .string($0) } ?? .null,
            "swarmTaskId": task.swarmTaskId.map { .string($0) } ?? .null,
            "swarmParentTaskId": task.swarmParentTaskId.map { .string($0) } ?? .null,
            "swarmDependencyIds": task.swarmDependencyIds.map { .array($0.map { .string($0) }) } ?? .null,
            "swarmDepth": task.swarmDepth.map { .number(Double($0)) } ?? .null,
            "swarmActorPath": task.swarmActorPath.map { .array($0.map { .string($0) }) } ?? .null,
            "createdAt": .string(ISO8601DateFormatter().string(from: task.createdAt)),
            "updatedAt": .string(ISO8601DateFormatter().string(from: task.updatedAt))
        ])
    }

    func normalizeChannelTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Channel"
        }
        return String(trimmed.prefix(160))
    }

    func normalizedProjectID(_ raw: String) -> String? {
        normalizedEntityID(raw)
    }

    func normalizedEntityID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil, trimmed.count <= 180 else {
            return nil
        }

        return trimmed
    }

    func normalizedChannelID(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/")
        guard !trimmed.isEmpty, trimmed.count <= 200, trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            throw ProjectError.invalidChannelID
        }
        return trimmed
    }

    func slugify(_ raw: String) -> String {
        let lower = raw.lowercased()
        let separated = lower.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return separated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func projectDirectoryURL(projectID: String) -> URL {
        workspaceRootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
    }

    func projectMetaDirectoryURL(projectID: String) -> URL {
        projectDirectoryURL(projectID: projectID).appendingPathComponent(".meta", isDirectory: true)
    }

    func projectTaskLogFileURL(projectID: String, taskID: String) -> URL {
        projectMetaDirectoryURL(projectID: projectID).appendingPathComponent("task-\(taskID).log")
    }

    func relativePathFromWorkspace(_ url: URL) -> String {
        let workspacePath = workspaceRootURL.path
        let targetPath = url.path
        if targetPath.hasPrefix(workspacePath) {
            let suffix = targetPath.dropFirst(workspacePath.count)
            return suffix.hasPrefix("/") ? String(suffix.dropFirst()) : String(suffix)
        }
        return targetPath
    }

}
