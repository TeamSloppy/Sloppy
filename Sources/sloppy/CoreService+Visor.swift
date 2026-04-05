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
        let taskSummary = await buildProjectTaskSummary()
        let bulletin = await runtime.generateVisorBulletin(taskSummary: taskSummary)
        await store.persistBulletin(bulletin)
        return bulletin
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
        if let visorModel, !visorModel.isEmpty, modelProvider.supportedModels.contains(visorModel) {
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
        if let visorModel, !visorModel.isEmpty, modelProvider.supportedModels.contains(visorModel) {
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
