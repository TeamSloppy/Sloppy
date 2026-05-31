import Foundation
import AgentRuntime
import Protocols
import PluginSDK
import AnyLanguageModel
import Logging

// MARK: - Visor

extension CoreService {
    public func getBulletins() async -> [MemoryBulletin] {
        await waitForStartup()
        let runtimeBulletins = await runtime.bulletins()
        if runtimeBulletins.isEmpty {
            return await store.listBulletins()
        }
        return runtimeBulletins
    }

    /// Creates worker instance from API request.
    public func postWorker(request: WorkerCreateRequest) async -> String {
        await waitForStartup()
        return await runtime.createWorker(spec: request.spec)
    }

    /// Reads artifact content from runtime or persistent storage.
    public func getArtifactContent(id: String) async -> ArtifactContentResponse? {
        await waitForStartup()
        if let runtimeArtifact = await runtime.artifactContent(id: id) {
            await store.persistArtifact(id: id, content: runtimeArtifact)
            return ArtifactContentResponse(id: id, content: runtimeArtifact)
        }

        if let storedArtifact = await store.artifactContent(id: id) {
            return ArtifactContentResponse(id: id, content: storedArtifact)
        }

        return nil
    }

    /// Returns true after Visor has completed its first supervision tick.
    public func isVisorReady() async -> Bool {
        await runtime.isVisorReady()
    }

    /// Sends a question to Visor and returns its answer.
    public func postVisorChat(question: String) async -> String {
        await waitForStartup()
        return await runtime.askVisor(question: question)
    }

    /// Sends a question to Visor and returns a stream of text delta chunks.
    public func streamVisorChat(question: String) async -> AsyncStream<String> {
        await waitForStartup()
        return await runtime.streamVisorAnswer(question: question)
    }

    /// Forces immediate visor bulletin generation and stores it.
    public func triggerVisorBulletin() async -> MemoryBulletin {
        await waitForStartup()
        await processAutonomousExecution()
        let taskSummary = await buildProjectTaskSummary()
        let bulletin = await runtime.generateVisorBulletin(taskSummary: taskSummary)
        await store.persistBulletin(bulletin)
        return bulletin
    }

    /// Processes autonomous task execution for all projects.
    public func processAutonomousExecution() async {
        let projects = await store.listProjects()
        for project in projects {
            guard project.autopilotSettings.enabled else { continue }
            await processProjectAutopilot(project)
        }
    }

    func processProjectAutopilot(_ initialProject: ProjectRecord) async {
        guard var project = await store.project(id: initialProject.id) else {
            return
        }

        let reconciliation = reconcileAutopilotGraph(project: &project)
        var readyTaskIDs = reconciliation.readyTaskIDs
        if reconciliation.changed {
            await store.saveProject(project)
        }
        for comment in reconciliation.comments {
            await appendSystemTaskComment(projectID: project.id, taskID: comment.taskID, content: comment.content)
        }

        let settings = project.autopilotSettings
        var activeCount = project.tasks.filter { task in
            isAutopilotExecutionTask(project: project, task: task) && activeAutopilotStatuses.contains(task.status)
        }.count
        var capacity = autopilotCapacity(settings: settings, activeCount: activeCount)
        guard capacity > 0 else {
            await launchAutopilotReadyTasks(projectID: project.id, taskIDs: readyTaskIDs)
            return
        }

        let candidates = project.tasks
            .filter { isEligibleAutopilotBacklogRoot(project: project, task: $0) }
            .sorted(by: sortAutopilotTasks)

        for root in candidates {
            guard capacity > 0 else { break }
            guard let rootIndex = project.tasks.firstIndex(where: { $0.id == root.id }) else {
                continue
            }
            let childTasks = project.tasks.filter { $0.parentTaskId == root.id }
            if childTasks.isEmpty {
                guard hasAutopilotDefaultAgent(project) else {
                    await blockAutopilotTask(
                        project: project,
                        taskID: root.id,
                        message: "Autopilot requires a default agent before it can execute task \(root.id)."
                    )
                    project = await store.project(id: project.id) ?? project
                    continue
                }

                do {
                    let planned = try await makeProjectAutopilotPlanner().plan(project: project, rootTask: root)
                    let newReadyIDs = createAutopilotChildTasks(
                        planned,
                        rootIndex: rootIndex,
                        project: &project,
                        capacity: capacity
                    )
                    readyTaskIDs.append(contentsOf: newReadyIDs)
                    activeCount += newReadyIDs.count
                    capacity = autopilotCapacity(settings: settings, activeCount: activeCount)
                    logger.info(
                        "project.autopilot.decomposed",
                        metadata: [
                            "project_id": .string(project.id),
                            "task_id": .string(root.id),
                            "subtask_count": .stringConvertible(planned.count)
                        ]
                    )
                    await store.saveProject(project)
                } catch {
                    await blockAutopilotTask(
                        project: project,
                        taskID: root.id,
                        message: "Autopilot planning failed: \(error.localizedDescription)"
                    )
                    project = await store.project(id: project.id) ?? project
                }
            } else {
                let releasable = releasableAutopilotChildren(project: project, parentTaskID: root.id)
                for taskID in releasable.prefix(capacity) {
                    if let index = project.tasks.firstIndex(where: { $0.id == taskID }) {
                        project.tasks[index].status = ProjectTaskStatus.ready.rawValue
                        project.tasks[index].updatedAt = Date()
                        readyTaskIDs.append(taskID)
                        capacity -= 1
                    }
                }
                if !releasable.isEmpty {
                    project.updatedAt = Date()
                    await store.saveProject(project)
                }
            }
        }

        await launchAutopilotReadyTasks(projectID: project.id, taskIDs: readyTaskIDs)
    }

    var activeAutopilotStatuses: Set<String> {
        [
            ProjectTaskStatus.ready.rawValue,
            ProjectTaskStatus.inProgress.rawValue,
            ProjectTaskStatus.needsReview.rawValue,
            ProjectTaskStatus.waitingInput.rawValue
        ]
    }

    func autopilotCapacity(settings: ProjectAutopilotSettings, activeCount: Int) -> Int {
        switch settings.mode {
        case .parallel:
            return max(0, settings.maxParallelTasks - activeCount)
        case .assistive, .sequential:
            return activeCount == 0 ? 1 : 0
        }
    }

    func hasAutopilotDefaultAgent(_ project: ProjectRecord) -> Bool {
        !(project.autopilotSettings.defaultAgentId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func isAutopilotManagedTask(project: ProjectRecord, task: ProjectTask) -> Bool {
        if normalizeWhitespace(task.createdBy ?? "") == "autopilot" {
            return true
        }
        return isEligibleAutopilotRoot(project: project, task: task)
    }

    func isAutopilotExecutionTask(project: ProjectRecord, task: ProjectTask) -> Bool {
        if normalizeWhitespace(task.createdBy ?? "") == "autopilot" {
            return true
        }
        return isEligibleAutopilotRoot(project: project, task: task)
            && !project.tasks.contains(where: { $0.parentTaskId == task.id })
    }

    func isEligibleAutopilotRoot(project: ProjectRecord, task: ProjectTask) -> Bool {
        guard task.parentTaskId == nil else { return false }
        let settings = project.autopilotSettings
        let included = Set(settings.includedTags.map { $0.lowercased() })
        let taskTags = Set(task.tags.map { $0.lowercased() })
        guard !included.isDisjoint(with: taskTags) else {
            return false
        }
        let trustedAuthors = Set(settings.trustedAuthors.map { $0.lowercased() })
        if !trustedAuthors.isEmpty {
            guard let createdBy = task.createdBy?.lowercased(),
                  trustedAuthors.contains(createdBy)
            else {
                return false
            }
        }
        return true
    }

    func isEligibleAutopilotBacklogRoot(project: ProjectRecord, task: ProjectTask) -> Bool {
        task.status == ProjectTaskStatus.backlog.rawValue && isEligibleAutopilotRoot(project: project, task: task)
    }

    func sortAutopilotTasks(_ lhs: ProjectTask, _ rhs: ProjectTask) -> Bool {
        if lhs.priority != rhs.priority {
            let priorities = ["high": 3, "medium": 2, "low": 1]
            return (priorities[lhs.priority] ?? 0) > (priorities[rhs.priority] ?? 0)
        }
        return lhs.createdAt < rhs.createdAt
    }

    struct AutopilotGraphReconciliation {
        var readyTaskIDs: [String] = []
        var comments: [(taskID: String, content: String)] = []
        var changed: Bool = false
    }

    func reconcileAutopilotGraph(project: inout ProjectRecord) -> AutopilotGraphReconciliation {
        var reconciliation = AutopilotGraphReconciliation()
        var readyTaskIDs: [String] = []
        let now = Date()
        let rootIDs = project.tasks
            .filter { isEligibleAutopilotRoot(project: project, task: $0) }
            .map(\.id)
        for rootID in rootIDs {
            let children = project.tasks.filter { $0.parentTaskId == rootID }
            guard !children.isEmpty else { continue }
            if let blockedChild = children.first(where: { $0.status == ProjectTaskStatus.blocked.rawValue }),
               let rootIndex = project.tasks.firstIndex(where: { $0.id == rootID }),
               project.tasks[rootIndex].status != ProjectTaskStatus.blocked.rawValue {
                project.tasks[rootIndex].status = ProjectTaskStatus.blocked.rawValue
                project.tasks[rootIndex].updatedAt = now
                reconciliation.changed = true
                reconciliation.comments.append((rootID, "Autopilot blocked because child task \(blockedChild.id) is blocked."))
            } else if children.allSatisfy({ $0.status == ProjectTaskStatus.done.rawValue }),
                      let rootIndex = project.tasks.firstIndex(where: { $0.id == rootID }),
                      project.tasks[rootIndex].status != ProjectTaskStatus.done.rawValue {
                project.tasks[rootIndex].status = ProjectTaskStatus.done.rawValue
                project.tasks[rootIndex].updatedAt = now
                reconciliation.changed = true
                reconciliation.comments.append((rootID, "Autopilot completed all child tasks."))
            }
        }

        var capacity = autopilotCapacity(
            settings: project.autopilotSettings,
            activeCount: project.tasks.filter { isAutopilotExecutionTask(project: project, task: $0) && activeAutopilotStatuses.contains($0.status) }.count
        )
        for rootID in rootIDs where capacity > 0 {
            for taskID in releasableAutopilotChildren(project: project, parentTaskID: rootID).prefix(capacity) {
                if let index = project.tasks.firstIndex(where: { $0.id == taskID }) {
                    project.tasks[index].status = ProjectTaskStatus.ready.rawValue
                    project.tasks[index].updatedAt = now
                    readyTaskIDs.append(taskID)
                    reconciliation.changed = true
                    capacity -= 1
                }
            }
        }
        if reconciliation.changed {
            project.updatedAt = now
        }
        reconciliation.readyTaskIDs = readyTaskIDs
        return reconciliation
    }

    func releasableAutopilotChildren(project: ProjectRecord, parentTaskID: String) -> [String] {
        let doneIDs = Set(project.tasks.filter { $0.status == ProjectTaskStatus.done.rawValue }.map(\.id))
        return project.tasks
            .filter { $0.parentTaskId == parentTaskID && $0.status == ProjectTaskStatus.backlog.rawValue }
            .filter { task in task.dependsOnTaskIds.allSatisfy { doneIDs.contains($0) } }
            .sorted(by: sortAutopilotTasks)
            .map(\.id)
    }

    func createAutopilotChildTasks(
        _ planned: [ProjectAutopilotPlanner.PlannedTask],
        rootIndex: Int,
        project: inout ProjectRecord,
        capacity: Int
    ) -> [String] {
        let root = project.tasks[rootIndex]
        let settings = project.autopilotSettings
        var tempToTaskID: [String: String] = [:]
        for plannedTask in planned {
            tempToTaskID[plannedTask.temporaryID] = nextProjectTaskID(for: project)
            project.tasks.append(
                ProjectTask(
                    id: tempToTaskID[plannedTask.temporaryID] ?? UUID().uuidString,
                    title: plannedTask.title,
                    description: "",
                    priority: root.priority,
                    status: ProjectTaskStatus.backlog.rawValue
                )
            )
        }

        let now = Date()
        var readyIDs: [String] = []
        for plannedTask in planned {
            guard let taskID = tempToTaskID[plannedTask.temporaryID],
                  let taskIndex = project.tasks.firstIndex(where: { $0.id == taskID })
            else {
                continue
            }
            let dependsOnTaskIds = plannedTask.dependsOnTemporaryIds.compactMap { tempToTaskID[$0] }
            let status: String
            if dependsOnTaskIds.isEmpty && readyIDs.count < capacity {
                status = ProjectTaskStatus.ready.rawValue
                readyIDs.append(taskID)
            } else {
                status = ProjectTaskStatus.backlog.rawValue
            }
            project.tasks[taskIndex] = ProjectTask(
                id: taskID,
                title: plannedTask.title,
                description: autopilotChildDescription(root: root, plannedTask: plannedTask, settings: settings),
                priority: root.priority,
                status: status,
                kind: plannedTask.kind,
                parentTaskId: root.id,
                createdBy: "autopilot",
                dependsOnTaskIds: dependsOnTaskIds,
                selectedModel: root.selectedModel,
                tags: normalizeTaskTags(root.tags + plannedTask.tags + settings.includedTags),
                createdAt: now,
                updatedAt: now
            )
        }

        project.tasks[rootIndex].status = ProjectTaskStatus.inProgress.rawValue
        project.tasks[rootIndex].updatedAt = now
        project.updatedAt = now
        return readyIDs
    }

    func autopilotChildDescription(
        root: ProjectTask,
        plannedTask: ProjectAutopilotPlanner.PlannedTask,
        settings: ProjectAutopilotSettings
    ) -> String {
        var lines = [
            plannedTask.description,
            "",
            "[Autopilot context]",
            "Parent objective: \(root.title)",
            root.description.isEmpty ? "Parent details: (none)" : "Parent details: \(root.description)",
            "",
            "[Allowed permissions]",
            "- Web/search: \(settings.canUseWeb ? "allowed" : "not allowed")",
            "- Edit files: \(settings.canEditFiles ? "allowed" : "not allowed")",
            "- Run commands: \(settings.canRunCommands ? "allowed" : "not allowed")",
            "- Start localhost: \(settings.canStartLocalhost ? "allowed" : "not allowed")",
            "- Commit: \(settings.canCommit ? "allowed" : "not allowed")",
            "- Push: \(settings.canPush ? "allowed" : "not allowed")",
            "",
            "[Verification requirement]",
            "Report concrete completion evidence before marking this task done."
        ]
        if settings.canStartLocalhost {
            lines.append("If you start a local server, report the localhost URL.")
        }
        if !plannedTask.verificationHints.isEmpty {
            lines.append(contentsOf: ["", "Verification hints:"])
            lines.append(contentsOf: plannedTask.verificationHints.map { "- \($0)" })
        }
        return normalizeTaskDescription(lines.joined(separator: "\n"))
    }

    func blockAutopilotTask(project: ProjectRecord, taskID: String, message: String) async {
        guard var latest = await store.project(id: project.id),
              let index = latest.tasks.firstIndex(where: { $0.id == taskID })
        else {
            return
        }
        let previousStatus = latest.tasks[index].status
        latest.tasks[index].status = ProjectTaskStatus.blocked.rawValue
        latest.tasks[index].updatedAt = Date()
        let note = "Autopilot blocked: \(message)"
        if !latest.tasks[index].description.contains(note) {
            latest.tasks[index].description = normalizeTaskDescription([latest.tasks[index].description, note].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        latest.updatedAt = Date()
        await store.saveProject(latest)
        await kanbanEventService.push(KanbanEvent(type: .taskUpdated, projectId: latest.id, task: latest.tasks[index]))
        await recordSystemStatusChange(projectID: latest.id, taskID: taskID, from: previousStatus, to: ProjectTaskStatus.blocked.rawValue, source: "autopilot")
        await appendSystemTaskComment(projectID: latest.id, taskID: taskID, content: note)
    }

    func launchAutopilotReadyTasks(projectID: String, taskIDs: [String]) async {
        var launched = Set<String>()
        for taskID in taskIDs where launched.insert(taskID).inserted {
            await handleTaskBecameReady(projectID: projectID, taskID: taskID)
        }
    }

    func makeProjectAutopilotPlanner() -> ProjectAutopilotPlanner {
        let modelProvider = self.modelProvider
        return ProjectAutopilotPlanner { prompt in
            guard let modelProvider else {
                return nil
            }
            guard let modelID = modelProvider.supportedModels.first else {
                return nil
            }
            let languageModel = try await modelProvider.createLanguageModel(for: modelID)
            let session = LanguageModelSession(model: languageModel, tools: [])
            let options = modelProvider.generationOptions(for: modelID, maxTokens: 4_096, reasoningEffort: nil)
            return try await session.respond(to: prompt, options: options).content
        }
    }

    func visorSchedulerRunning() async -> Bool {
        await visorScheduler?.running() ?? false
    }

    func buildProjectTaskSummary() async -> String? {
        let projects = await store.listProjects()
        var lines: [String] = []
        for project in projects {
            let active = project.tasks.filter { activeProjectTaskStatuses.contains($0.status) }
            guard !active.isEmpty else { continue }
            let taskEntries = active.prefix(20).map { task in
                let actor = task.claimedActorId ?? task.actorId ?? ""
                let actorSuffix = actor.isEmpty ? "" : " @\(actor)"
                return "[\(task.id)] \(task.title) (\(task.status))\(actorSuffix)"
            }
            lines.append("Project \(project.name): \(taskEntries.joined(separator: ", "))")
        }
        return lines.isEmpty ? nil : "Active tasks: " + lines.joined(separator: "; ")
    }

    func buildVisorSchedulerConfig() -> VisorSchedulerConfig {
        let scheduler = currentConfig.visor.scheduler
        return VisorSchedulerConfig(
            interval: .seconds(max(1, scheduler.intervalSeconds)),
            jitter: .seconds(max(0, scheduler.jitterSeconds))
        )
    }

    /// Builds a completion closure for Visor bulletin synthesis.
    /// Uses `visorModel` when specified (e.g. a cheaper model), otherwise falls back to the default model.
    static func buildVisorCompletionProvider(
        modelProvider: (any ModelProvider)?,
        visorModel: String?,
        resolvedModels: [String]
    ) -> (@Sendable (String, Int) async -> String?)? {
        guard let modelProvider else {
            return nil
        }

        let activeModel: String
        if let visorModel, !visorModel.isEmpty, modelProvider.supports(modelName: visorModel) {
            activeModel = visorModel
        } else if let fallback = modelProvider.supportedModels.first ?? resolvedModels.first {
            activeModel = fallback
        } else {
            return nil
        }

        return { @Sendable prompt, maxTokens in
            guard let languageModel = try? await modelProvider.createLanguageModel(for: activeModel) else {
                return nil
            }
            let session = LanguageModelSession(model: languageModel, tools: [])
            let options = modelProvider.generationOptions(for: activeModel, maxTokens: maxTokens, reasoningEffort: nil)
            return try? await session.respond(to: prompt, options: options).content
        }
    }

    static func buildVisorStreamingProvider(
        modelProvider: (any ModelProvider)?,
        visorModel: String?,
        resolvedModels: [String]
    ) -> (@Sendable (String, Int) -> AsyncStream<String>)? {
        guard let modelProvider else {
            return nil
        }

        let activeModel: String
        if let visorModel, !visorModel.isEmpty, modelProvider.supports(modelName: visorModel) {
            activeModel = visorModel
        } else if let fallback = modelProvider.supportedModels.first ?? resolvedModels.first {
            activeModel = fallback
        } else {
            return nil
        }

        return { @Sendable prompt, maxTokens in
            AsyncStream<String> { continuation in
                Task {
                    guard let languageModel = try? await modelProvider.createLanguageModel(for: activeModel) else {
                        continuation.finish()
                        return
                    }
                    let session = LanguageModelSession(model: languageModel, tools: [])
                    let options = modelProvider.generationOptions(for: activeModel, maxTokens: maxTokens, reasoningEffort: nil)
                    var previousLength = 0
                    do {
                        let stream = session.streamResponse(
                            to: Prompt(prompt),
                            generating: GeneratedContent.self,
                            includeSchemaInPrompt: false,
                            options: options
                        )
                        for try await snapshot in stream {
                            let full: String
                            if case .string(let value) = snapshot.rawContent.kind {
                                full = value
                            } else {
                                full = snapshot.rawContent.jsonString
                            }
                            guard full.count > previousLength else { continue }
                            let startIndex = full.index(full.startIndex, offsetBy: previousLength)
                            let delta = String(full[startIndex...])
                            continuation.yield(delta)
                            previousLength = full.count
                        }
                    } catch {
                        // stream ends gracefully on error
                    }
                    continuation.finish()
                }
            }
        }
    }

    func enrichMessageWithTaskReferences(_ content: String) async -> String {
        let references = extractTaskReferences(from: content)
        guard !references.isEmpty else {
            return content
        }

        var lines: [String] = [content, "", "[task_reference_context_v1]"]
        for reference in references {
            if let record = try? await getProjectTask(taskReference: reference) {
                let description = record.task.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let compactDescription = description.isEmpty ? "(no description)" : String(description.prefix(320))
                lines.append(
                    "#\(reference) -> project=\(record.projectId), title=\(record.task.title), status=\(record.task.status), priority=\(record.task.priority)"
                )
                lines.append("details: \(compactDescription)")
            } else {
                lines.append("#\(reference) -> task_not_found")
            }
        }
        lines.append("Use this task context when answering the user.")
        return lines.joined(separator: "\n")
    }

    /// Exposes worker snapshots for observability endpoints.
    public func workerSnapshots() async -> [WorkerSnapshot] {
        await waitForStartup()
        return await runtime.workerSnapshots()
    }

    /// Lists dashboard projects with channels and task board data.
}
