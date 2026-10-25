import Foundation
import Protocols
import PluginSDK
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func canonicalWorkflowDirectory(_ path: String) -> String {
    var url = URL(fileURLWithPath: path).standardizedFileURL
    var suffix: [String] = []
    while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
        suffix.insert(url.lastPathComponent, at: 0)
        url.deleteLastPathComponent()
    }
    #if !os(Windows)
    if let resolved = realpath(url.path, nil) {
        let base = String(cString: resolved); free(resolved)
        return ([base] + suffix).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
    }
    #endif
    return path
}

extension CoreService {
    func workflowTaskOwner(projectID: String, taskID: String) -> String? {
        let key = projectID + ":" + taskID
        guard let owner = workflowTaskOwners[key] else { return nil }
        if !activeWorkflowRuns.contains(owner), let state = try? workflowExecutionFiles.load(owner), [.completed, .failed, .cancelled].contains(state.run.status) {
            workflowTaskOwners[key] = nil
            return nil
        }
        return owner
    }

    func registerWorkflowTaskOwner(_ state: WorkflowExecutionState) {
        guard let task = state.run.taskId else { return }
        let key = state.run.projectId + ":" + task
        if [.completed, .failed, .cancelled].contains(state.run.status) {
            if workflowTaskOwners[key] == state.run.id { workflowTaskOwners[key] = nil }
        } else {
            if let previous = workflowTaskOwners[key], let saved = try? workflowExecutionFiles.load(previous),
               [.completed, .failed, .cancelled].contains(saved.run.status) {
                workflowTaskOwners[key] = state.run.id
                return
            }
            let owner = workflowTaskOwner(projectID: state.run.projectId, taskID: task)
            let existingDepth = owner.flatMap { try? workflowExecutionFiles.load($0)?.originalInput["__workflowAncestors"]?.asArray?.count } ?? 1
            let depth = state.originalInput["__workflowAncestors"]?.asArray?.count ?? 1
            if owner == nil || depth < existingDepth { workflowTaskOwners[key] = state.run.id }
        }
    }

    func workflowOwnsDescendant(_ ancestor: String, runID: String) -> Bool {
        var pending = [ancestor]
        var visited: Set<String> = []
        while let id = pending.popLast(), visited.count < 512 {
            if id == runID { return true }
            guard visited.insert(id).inserted, let state = try? workflowExecutionFiles.load(id) else { continue }
            pending += state.steps.filter { step in
                state.definition.nodes.contains { $0.id == step.nodeId && WorkflowGraphContracts.blockKind($0) == "sub_workflow" }
            }.compactMap { $0.output["childRunId"]?.asString }
        }
        return false
    }

    func workflowInput(projectID: String, request: WorkflowRunCreateRequest) async throws -> [String: JSONValue] {
        var input = request.input
        if let taskID = request.taskId {
            let project = try await getProject(id: projectID)
            guard let task = project.tasks.first(where: { $0.id == taskID }), !task.isArchived else { throw ProjectError.invalidTaskID }
            guard !projectExecutionSessions.values.contains(where: { $0.projectID == projectID && $0.taskID == taskID }) else { throw ProjectError.conflict }
            input["task"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(task))
        } else { input.removeValue(forKey: "task") }
        return input
    }

    func planWorkflowEnvironment(projectID: String, runID: String, request: WorkflowRunCreateRequest) async throws -> WorkflowEnvironmentBinding {
        let project = try await getProject(id: projectID)
        let task = project.tasks.first { $0.id == request.taskId }
        let choice = request.environment ?? .init()
        let root = canonicalWorkflowDirectory(try await resolveProjectWorkspaceRoot(projectID: projectID).path)
        let provider = sourceControlProvider(for: project, task: task)
        var path = root
        var revision: String?
        if choice.mode != .project {
            let info = await provider.inspectRepository(at: root)
            guard info.isRepository, provider.capabilities.contains(.worktrees) else {
                throw WorkflowGraphContracts.Violation("The project provider does not support worktrees.")
            }
            if choice.mode == .newWorktree {
                let ref = choice.baseRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD"
                guard !ref.isEmpty else { throw WorkflowError.invalidPayload }
                revision = provider.id == Self.defaultSourceControlProviderID
                    ? try await gitWorktreeService.resolveRevision(repoPath: root, reference: ref)
                    : ref == "HEAD" ? info.head : ref
                guard revision != nil else { throw WorkflowError.invalidPayload }
                path = provider.worktreePath(repoPath: root, taskId: runID, worktreeRootPath: defaultWorktreeRootPath(projectID: projectID))
            } else if choice.mode == .taskWorktree {
                guard let task, task.worktreeBranch != nil else { throw ProjectError.invalidTaskID }
                path = provider.worktreePath(repoPath: root, taskId: task.id,
                    worktreeRootPath: project.worktreeRootPath ?? defaultWorktreeRootPath(projectID: projectID))
            } else {
                guard let selected = choice.path, selected.hasPrefix("/") else { throw WorkflowError.invalidPayload }
                path = selected
            }
        }
        var binding = WorkflowEnvironmentBinding(request: choice, projectRoot: root,
            workingDirectory: canonicalWorkflowDirectory(path), providerId: provider.id, baseRevision: revision)
        if choice.mode != .newWorktree {
            try await validateWorkflowEnvironment(binding)
            if choice.mode != .project { binding.branch = try await provider.currentBranch(at: binding.workingDirectory) }
        }
        return binding
    }

    func validateWorkflowEnvironment(_ binding: WorkflowEnvironmentBinding) async throws {
        let url = URL(fileURLWithPath: binding.workingDirectory)
        var directory: ObjCBool = false
        guard url.path == canonicalWorkflowDirectory(url.path),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw WorkflowGraphContracts.Violation("The pinned workflow directory is missing or was replaced by a symlink.")
        }
        if binding.request.mode != .project {
            guard let provider = sourceControlProviders[binding.providerId], (await provider.inspectRepository(at: url.path)).isRepository else {
                throw WorkflowGraphContracts.Violation("The pinned source-control provider or worktree is unavailable.")
            }
            if provider.id == Self.defaultSourceControlProviderID {
                let original = try await gitWorktreeService.commonDirectory(repoPath: binding.projectRoot)
                guard try await gitWorktreeService.commonDirectory(repoPath: url.path) == original else {
                    throw WorkflowGraphContracts.Violation("Selected worktree belongs to another repository.")
                }
            }
            if let branch = binding.branch, try await provider.currentBranch(at: url.path) != branch {
                throw WorkflowGraphContracts.Violation("The pinned worktree branch was changed.")
            }
        }
    }

    func prepareWorkflowEnvironment(_ journal: WorkflowExecutionJournal) async throws -> Bool {
        let state = await journal.snapshot()
        guard var binding = state.run.environment else { return true } // Legacy runs keep their original execution behavior.
        do {
            if binding.preparation == .setup || binding.preparation == .blocked {
                throw WorkflowGraphContracts.Violation("Environment setup was interrupted. Reconcile its effects before explicitly retrying.")
            }
            if binding.preparation == .failed { return false }
            if binding.request.mode == .newWorktree && binding.preparation != .ready {
                guard let provider = sourceControlProviders[binding.providerId] else { throw WorkflowError.invalidPayload }
                if binding.preparation == .pending {
                    binding.preparation = .creating
                    try await journal.bindEnvironment(binding)
                    let result = try await provider.createWorktree(repoPath: binding.projectRoot, taskId: state.run.id,
                        baseBranch: binding.baseRevision ?? "HEAD", worktreeRootPath: URL(fileURLWithPath: binding.workingDirectory).deletingLastPathComponent().path)
                    guard result.worktreePath == binding.workingDirectory else { throw WorkflowError.invalidPayload }
                    binding.branch = result.branchName
                } else {
                    // Creation may have completed before the response was checkpointed. Adopt only the exact registered checkout.
                    try await validateWorkflowEnvironment(binding)
                    binding.branch = try await provider.currentBranch(at: binding.workingDirectory)
                }
            }
            try await validateWorkflowEnvironment(binding)
            if binding.preparation != .ready, let command = binding.request.setupCommand, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                binding.preparation = .setup
                try await journal.bindEnvironment(binding)
                let result = await toolExecution.invoke(agentID: "workflow", sessionID: "workflow-\(state.run.id)",
                    request: .init(tool: "runtime.exec", arguments: ["command": .string("bash"), "arguments": .array([.string("-lc"), .string(command)]), "cwd": .string(binding.workingDirectory)]),
                    policy: AgentToolsPolicy(), currentProjectID: state.run.projectId, currentDirectoryURL: URL(fileURLWithPath: binding.workingDirectory))
                guard result.ok, result.data?.asObject?["exitCode"]?.asNumber == 0 else {
                    try await journal.stopPreparation(binding, message: "Environment setup failed: \(result.error?.message ?? String(describing: result.data))", blocked: false)
                    return false
                }
            }
            binding.preparation = .ready
            try await journal.bindEnvironment(binding)
            return true
        } catch {
            if await journal.suspended { throw CancellationError() }
            try await journal.stopPreparation(binding, message: String(describing: error), blocked: true)
            return false
        }
    }

    func workflowSessionDirectory(_ sessionID: String) -> String? {
        if let path = workflowSessionDirectories[sessionID] { return path }
        // The workflow checkpoint is authoritative across session replies and server restarts.
        for id in (try? workflowExecutionFiles.identifiers()) ?? [] {
            guard let state = try? workflowExecutionFiles.load(id) else { continue }
            if let step = state.steps.last(where: { $0.output["sessionId"]?.asString == sessionID || $0.output["compactSessionId"]?.asString == sessionID }),
               let path = step.input["environment"]?.asObject?["workingDirectory"]?.asString ?? state.run.environment?.workingDirectory {
                workflowSessionDirectories[sessionID] = path
                return path
            }
        }
        return nil
    }
}
