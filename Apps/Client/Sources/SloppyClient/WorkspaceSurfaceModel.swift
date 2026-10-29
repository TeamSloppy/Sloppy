import Foundation
import Observation
import SloppyClientCore

enum WorkspaceTool: String, CaseIterable {
    case review, files, browser, terminal
    var title: String { rawValue.capitalized }
}

enum WorkspaceCreation: String { case scheduled, canvas, automation }
enum ScheduledTaskFilter: String { case all = "All", active = "Active", paused = "Paused" }
enum WorkspaceReviewFilter: String { case all = "All", reviewing = "Reviewing", authored = "Authored" }

@Observable
@MainActor
final class WorkspaceSurfaceModel {
    let api: SloppyAPIClient
    let canvas: WorkspaceCanvasModel
    var projectSection: ProjectWorkspaceSection = .kanban
    var findings: [ProactiveFinding] = []
    var scheduled: [ScheduledTask] = []
    var reviews: [CodeReviewItem] = []
    var sites: [PublishedSiteRecord] = []
    var canvases: [CanvasWorkspaceSummary] = []
    var automations: [ProjectAutomationDefinition] = []
    var automationRuns: [ProjectAutomationRun] = []
    var runningAutomationIDs: Set<String> = []
    var selectedAutomationRunID: String?
    var agents: [APIAgentRecord] = []
    var errors: [String] = []
    var isLoading = false
    var isSaving = false
    var query = ""
    var scheduleFilter: ScheduledTaskFilter = .all
    var reviewFilter: WorkspaceReviewFilter = .all
    var selectedScheduledID: String?
    var selectedReview: CodeReviewDetail?
    var selectedReviewID: String?
    var isLoadingReview = false
    var sourceControl: ProjectWorkingTreeSourceControlResponse?
    var sourceControlError: String?
    var tool: WorkspaceTool?
    var files: [ProjectFileEntry] = []
    var filePath = ""
    var fileContent: ProjectFileContentResponse?
    var fileSearchQuery = ""
    var fileSearchResults: [ProjectFileSearchEntry] = []
    var isSearchingFiles = false
    @ObservationIgnored private var fileSearchTask: Task<Void, Never>?
    private var searchGeneration = 0
    var toolError: String?
    var creation: WorkspaceCreation?
    var creationName = ""
    var creationSchedule = "0 9 * * *"
    var creationCommand = ""
    var creationChannelID = ""
    var creationAgentID = ""
    var creationWorkflowID = ""
    var creationRepository = ""
    var creationTrigger: ProjectAutomationTriggerKind = .manual
    var creationTaskMode: ProjectAutomationTaskMode = .none
    var creationPermissions: ProjectAutomationPermissionsScope = .private
    private var loadGeneration = 0
    private var sourceGeneration = 0
    private var fileGeneration = 0

    init(api: SloppyAPIClient) { self.api = api; canvas = WorkspaceCanvasModel(service: api.workspace) }

    func beginCreation(_ kind: WorkspaceCreation, agentID: String? = nil, channelID: String? = nil) {
        creationName = ""
        creationCommand = ""
        creationWorkflowID = ""
        creationRepository = ""
        creationTrigger = .manual
        creationTaskMode = .none
        creationPermissions = .private
        creationAgentID = agentID ?? agents.first?.id ?? ""
        creationChannelID = channelID ?? ""
        errors = []
        creation = kind
    }

    var unreadCount: Int { findings.filter { $0.readAt == nil && Self.active($0) }.count }
    var visibleFindings: [ProactiveFinding] { findings.filter { Self.active($0) && matches($0.reason + " " + $0.evidence) } }
    var visibleScheduled: [ScheduledTask] {
        scheduled.filter {
            matches($0.command + " " + $0.agentId + " " + $0.schedule)
                && (scheduleFilter == .all || (scheduleFilter == .active ? $0.enabled : !$0.enabled))
        }
    }
    var visibleReviews: [CodeReviewItem] {
        reviews.filter {
            matches($0.title + " " + $0.repository)
                && (reviewFilter == .all || $0.roles.contains(reviewFilter == .authored ? .authored : .reviewRequested))
        }
    }
    var selectedScheduled: ScheduledTask? { scheduled.first { $0.id == selectedScheduledID } }

    func matches(_ value: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || value.localizedCaseInsensitiveContains(normalized)
    }

    static func active(_ finding: ProactiveFinding, at date: Date = Date()) -> Bool {
        finding.outcome != .quiet && finding.dismissedAt == nil && finding.resolvedAt == nil
            && (finding.snoozedUntil.map { $0 <= date } ?? true)
    }

    func load(_ section: WorkspaceSection, project: APIProjectRecord? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errors = []
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            switch section {
            case .attention, .scheduled:
                let loadedAgents = try await api.fetchAgents()
                var newFindings: [ProactiveFinding] = []
                var newScheduled: [ScheduledTask] = []
                var failures: [String] = []
                for agent in loadedAgents {
                    do {
                        if section == .attention {
                            let inbox = try await api.workspace.attention(agentID: agent.id)
                            newFindings += inbox.findings
                            failures += inbox.sourceErrors.sorted { $0.key < $1.key }.map { "\(agent.displayName) · \($0.key): \($0.value)" }
                            if let error = inbox.lastAnalysisError { failures.append("\(agent.displayName): \(error)") }
                        } else {
                            newScheduled += try await api.workspace.scheduledTasks(agentID: agent.id)
                        }
                    } catch { failures.append("\(agent.displayName): \(error.localizedDescription)") }
                }
                guard generation == loadGeneration else { return }
                agents = loadedAgents
                errors = failures
                if section == .attention { findings = newFindings.sorted { $0.createdAt > $1.createdAt } }
                else { scheduled = newScheduled.sorted { $0.updatedAt > $1.updatedAt } }
            case .pullRequests:
                let response = try await api.workspace.pullRequests()
                guard generation == loadGeneration else { return }
                reviews = response.items
                errors = response.failures.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            case .sites:
                let response = try await api.workspace.sites()
                guard generation == loadGeneration else { return }
                sites = response
            case .project:
                guard let project else { return }
                switch projectSection {
                case .workspaces:
                    let response = try await api.workspace.workspaces(projectID: project.id)
                    guard generation == loadGeneration else { return }
                    canvases = response
                case .automation:
                    let response = try await api.workspace.automations(projectID: project.id)
                    guard generation == loadGeneration else { return }
                    automations = response
                    let runs = try await api.workspace.automationRuns(projectID: project.id)
                    guard generation == loadGeneration else { return }
                    automationRuns = runs.filter { $0.projectId == project.id }.sorted { $0.startedAt > $1.startedAt }
                case .kanban, .chats: break
                }
            default: break
            }
        } catch {
            if generation == loadGeneration { errors = [error.localizedDescription] }
        }
    }

    func loadSourceControl(project: APIProjectRecord?) async {
        sourceGeneration += 1
        let generation = sourceGeneration
        sourceControl = nil
        sourceControlError = nil
        guard let project else { return }
        do {
            let response = try await api.workspace.sourceControl(projectID: project.id)
            guard generation == sourceGeneration else { return }
            sourceControl = response
        } catch {
            if generation == sourceGeneration { sourceControlError = error.localizedDescription }
        }
    }

    func openReview(_ item: CodeReviewItem) async {
        selectedReviewID = item.id
        selectedReview = nil
        isLoadingReview = true
        defer { if selectedReviewID == item.id { isLoadingReview = false } }
        do {
            let detail = try await api.workspace.pullRequest(item)
            if selectedReviewID == item.id { selectedReview = detail }
        } catch {
            if selectedReviewID == item.id { errors = [error.localizedDescription] }
        }
    }

    func act(_ finding: ProactiveFinding, action: ProactiveFindingActionRequest.Action) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await api.workspace.updateFinding(finding, action: action)
            if let index = findings.firstIndex(where: { $0.id == finding.id }) { findings[index] = updated }
        } catch { errors = [error.localizedDescription] }
    }

    func toggleScheduled(_ task: ScheduledTask) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await api.workspace.updateScheduledTask(task, enabled: !task.enabled)
            if let index = scheduled.firstIndex(where: { $0.id == task.id }) { scheduled[index] = updated }
        } catch { errors = [error.localizedDescription] }
    }

    func openFiles(project: APIProjectRecord, path: String = "") async {
        fileSearchTask?.cancel()
        searchGeneration += 1
        isSearchingFiles = false
        fileSearchQuery = ""
        fileSearchResults = []
        fileGeneration += 1
        let generation = fileGeneration
        tool = .files
        toolError = nil
        do {
            let entries = try await api.workspace.files(projectID: project.id, path: path)
            guard generation == fileGeneration else { return }
            files = entries.sorted { $0.type != $1.type ? $0.type == .directory : $0.name < $1.name }
            filePath = path
            fileContent = nil
        } catch { if generation == fileGeneration { toolError = error.localizedDescription } }
    }

    func searchFiles(project: APIProjectRecord) {
        fileSearchTask?.cancel()
        searchGeneration += 1
        fileGeneration += 1
        let generation = searchGeneration
        let term = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        fileContent = nil
        toolError = nil
        guard !term.isEmpty else { fileSearchResults = []; isSearchingFiles = false; return }
        isSearchingFiles = true
        fileSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let results = try await api.workspace.searchFiles(projectID: project.id, term: term)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                fileSearchResults = results
                isSearchingFiles = false
            } catch {
                guard !Task.isCancelled, generation == searchGeneration else { return }
                toolError = error.localizedDescription
                isSearchingFiles = false
            }
        }
    }

    func openFile(_ entry: ProjectFileEntry, project: APIProjectRecord) async {
        let path = entry.path ?? (filePath.isEmpty ? entry.name : filePath + "/" + entry.name)
        if entry.type == .directory { await openFiles(project: project, path: path); return }
        fileGeneration += 1
        let generation = fileGeneration
        do {
            let content = try await api.workspace.file(projectID: project.id, path: path)
            if generation == fileGeneration { fileContent = content }
        } catch { if generation == fileGeneration { toolError = error.localizedDescription } }
    }

    func saveCreation(project: APIProjectRecord?) async {
        guard let creation, !isSaving else { return }
        errors = []
        guard creation == .scheduled || !creationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errors = ["Enter a name."]; return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            switch creation {
            case .scheduled:
                guard !creationAgentID.isEmpty, !creationChannelID.isEmpty, !creationCommand.isEmpty else {
                    errors = ["Choose an agent and enter a channel and a prompt."]; return
                }
                let task = try await api.workspace.createScheduledTask(agentID: creationAgentID,
                    request: ScheduledTaskCreateRequest(channelId: creationChannelID, schedule: creationSchedule, command: creationCommand))
                scheduled.insert(task, at: 0)
                selectedScheduledID = task.id
            case .canvas:
                guard let project else { return }
                let canvas = try await api.workspace.createWorkspace(title: creationName, projectID: project.id)
                canvases.append(canvas)
                await self.canvas.open(canvas)
            case .automation:
                guard let project, !creationWorkflowID.isEmpty, !creationRepository.isEmpty else {
                    errors = ["Enter a workflow ID and repository."]; return
                }
                let repository = creationRepository.trimmingCharacters(in: .whitespacesAndNewlines)
                guard repository.split(separator: "/").count == 2, !repository.contains(" ") else {
                    errors = ["Enter the repository as owner/repo."]; return
                }
                let triggerConfig: [String: ProjectAutomationJSONValue]
                switch creationTrigger {
                case .cron: triggerConfig = ["schedule": .string(creationSchedule)]
                case .webhook:
                    guard !creationCommand.isEmpty else { errors = ["Enter a webhook secret ID."]; return }
                    triggerConfig = ["secretId": .string(creationCommand)]
                default: triggerConfig = [:]
                }
                let automation = try await api.workspace.createAutomation(projectID: project.id,
                    request: ProjectAutomationDefinitionUpsertRequest(name: creationName, workflowId: creationWorkflowID,
                        repositoryFullName: repository, trigger: ProjectAutomationTrigger(type: creationTrigger, config: triggerConfig),
                        taskMode: creationTaskMode, permissionsScope: creationPermissions))
                automations.append(automation)
            }
            self.creation = nil
        } catch { errors = [error.localizedDescription] }
    }

    func runAutomation(_ automation: ProjectAutomationDefinition) async {
        guard automation.enabled, runningAutomationIDs.insert(automation.id).inserted else { return }
        defer { runningAutomationIDs.remove(automation.id) }
        do {
            let result = try await api.workspace.runAutomation(automation)
            guard result.run.projectId == automation.projectId else { throw APIError.invalidResponse }
            automationRuns.removeAll { $0.id == result.run.id }
            automationRuns.insert(result.run, at: 0)
            selectedAutomationRunID = result.run.id
        } catch { errors = [error.localizedDescription] }
    }
}
