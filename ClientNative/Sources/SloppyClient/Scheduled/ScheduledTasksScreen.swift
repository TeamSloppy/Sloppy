import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

private enum ScheduledTaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case paused = "Paused"

    var id: Self { self }
}

@Observable
@MainActor
private final class ScheduledTasksViewModel {
    let apiClient: SloppyAPIClient
    var agents: [APIAgentRecord] = []
    var tasks: [ScheduledTask] = []
    var selectedTaskID: ScheduledTask.ID?
    var isLoading = false
    var errorMessage: String?

    init(apiClient: SloppyAPIClient) {
        self.apiClient = apiClient
    }

    var selectedTask: ScheduledTask? {
        tasks.first { $0.id == selectedTaskID }
    }

    func agentName(for id: String) -> String {
        agents.first { $0.id == id }?.displayName ?? id
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedAgents = try await apiClient.fetchAgents()
            let client = apiClient
            let loadedTasks = try await withThrowingTaskGroup(of: [ScheduledTask].self) { group in
                for agent in loadedAgents {
                    group.addTask {
                        try await client.fetchScheduledTasks(agentId: agent.id)
                    }
                }
                var result: [ScheduledTask] = []
                for try await agentTasks in group {
                    result.append(contentsOf: agentTasks)
                }
                return result.sorted { $0.updatedAt > $1.updatedAt }
            }
            agents = loadedAgents
            tasks = loadedTasks
            if selectedTaskID == nil || !loadedTasks.contains(where: { $0.id == selectedTaskID }) {
                selectedTaskID = loadedTasks.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: ScheduledTaskDraft) async throws {
        if let taskID = draft.taskID {
            _ = try await apiClient.updateScheduledTask(
                agentId: draft.agentID,
                taskId: taskID,
                request: ScheduledTaskUpdateRequest(
                    channelId: draft.channelID,
                    schedule: draft.schedule,
                    command: draft.command,
                    enabled: draft.enabled
                )
            )
        } else {
            _ = try await apiClient.createScheduledTask(
                agentId: draft.agentID,
                request: ScheduledTaskCreateRequest(
                    channelId: draft.channelID,
                    schedule: draft.schedule,
                    command: draft.command,
                    enabled: draft.enabled
                )
            )
        }
        await load()
    }

    func setEnabled(_ enabled: Bool, for task: ScheduledTask) async {
        do {
            _ = try await apiClient.updateScheduledTask(
                agentId: task.agentId,
                taskId: task.id,
                request: ScheduledTaskUpdateRequest(enabled: enabled)
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ task: ScheduledTask) async {
        do {
            try await apiClient.deleteScheduledTask(agentId: task.agentId, taskId: task.id)
            selectedTaskID = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ScheduledTaskDraft {
    var taskID: String?
    var agentID: String
    var channelID: String
    var schedule: String
    var command: String
    var enabled: Bool

    init(task: ScheduledTask? = nil, defaultAgentID: String = "") {
        taskID = task?.id
        agentID = task?.agentId ?? defaultAgentID
        channelID = task?.channelId ?? "main"
        schedule = task?.schedule ?? "0 9 * * *"
        command = task?.command ?? ""
        enabled = task?.enabled ?? true
    }
}

@MainActor
struct ScheduledTasksScreen: View {
    @State private var viewModel: ScheduledTasksViewModel
    @State private var filter: ScheduledTaskFilter = .all
    @State private var searchText = ""
    @State private var presentedDraft: ScheduledTaskDraft?
    @Environment(\.theme) private var theme

    init(apiClient: SloppyAPIClient) {
        _viewModel = State(initialValue: ScheduledTasksViewModel(apiClient: apiClient))
    }

    private var filteredTasks: [ScheduledTask] {
        viewModel.tasks.filter { task in
            let matchesFilter = switch filter {
            case .all: true
            case .active: task.enabled
            case .paused: !task.enabled
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesFilter && (query.isEmpty
                || task.command.localizedCaseInsensitiveContains(query)
                || task.schedule.localizedCaseInsensitiveContains(query)
                || viewModel.agentName(for: task.agentId).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            taskList
                .frame(minWidth: 340, idealWidth: 430, maxWidth: 520)
            Divider()
            detail
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.load() }
        .sheet(item: $presentedDraft) { draft in
            ScheduledTaskEditor(
                draft: draft,
                agents: viewModel.agents,
                onSave: { updated in try await viewModel.save(updated) }
            )
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(ScheduledTaskFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button {
                    presentedDraft = ScheduledTaskDraft(defaultAgentID: viewModel.agents.first?.id ?? "")
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .disabled(viewModel.agents.isEmpty)
            }
            .padding()

            TextField("Search scheduled tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()

            if viewModel.isLoading && viewModel.tasks.isEmpty {
                ProgressView("Loading scheduled tasks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Tasks",
                    systemImage: "clock",
                    description: Text(searchText.isEmpty ? "Create a recurring task to see it here." : "Try another search or filter.")
                )
            } else {
                List(filteredTasks, selection: $viewModel.selectedTaskID) { task in
                    ScheduledTaskRow(task: task, agentName: viewModel.agentName(for: task.agentId))
                        .tag(task.id)
                }
                .listStyle(.sidebar)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let task = viewModel.selectedTask {
            ScheduledTaskDetail(
                task: task,
                agentName: viewModel.agentName(for: task.agentId),
                onEdit: { presentedDraft = ScheduledTaskDraft(task: task) },
                onToggle: { enabled in Task { await viewModel.setEnabled(enabled, for: task) } },
                onDelete: { Task { await viewModel.delete(task) } }
            )
        } else {
            ContentUnavailableView("Select a Scheduled Task", systemImage: "clock")
        }
    }
}

private struct ScheduledTaskRow: View {
    let task: ScheduledTask
    let agentName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.enabled ? "clock.fill" : "pause.circle")
                .foregroundColor(task.enabled ? .blue : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.command).fontWeight(.medium).lineLimit(1)
                Text("\(agentName) · \(CronDescription.describe(task.schedule))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ScheduledTaskDetail: View {
    let task: ScheduledTask
    let agentName: String
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(task.enabled ? "Active" : "Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(task.enabled ? .blue : .secondary)
                    Spacer()
                    Button(task.enabled ? "Pause" : "Resume") { onToggle(!task.enabled) }
                    Button("Edit", action: onEdit)
                    Menu {
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: { Image(systemName: "ellipsis") }
                }

                Text(task.command)
                    .font(.title2.weight(.semibold))

                GroupBox("Details") {
                    LabeledContent("Agent", value: agentName)
                    Divider()
                    LabeledContent("Channel", value: task.channelId)
                }

                GroupBox("Frequency") {
                    LabeledContent("Repeat", value: CronDescription.describe(task.schedule))
                    Divider()
                    LabeledContent("Cron", value: task.schedule)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct ScheduledTaskEditor: View {
    @State var draft: ScheduledTaskDraft
    let agents: [APIAgentRecord]
    let onSave: (ScheduledTaskDraft) async throws -> Void
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.taskID == nil ? "Create Scheduled Task" : "Edit Scheduled Task")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Agent", selection: $draft.agentID) {
                    ForEach(agents) { agent in Text(agent.displayName).tag(agent.id) }
                }
                TextField("Channel", text: $draft.channelID)
                TextField("Cron schedule", text: $draft.schedule)
                TextField("Task", text: $draft.command, axis: .vertical)
                    .lineLimit(3...7)
                Toggle("Active", isOn: $draft.enabled)
            }
            .formStyle(.grouped)

            Text(CronDescription.describe(draft.schedule))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    isSaving = true
                    Task {
                        do {
                            try await onSave(draft)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isSaving = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || draft.agentID.isEmpty || draft.channelID.isEmpty || draft.schedule.isEmpty || draft.command.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

extension ScheduledTaskDraft: Identifiable {
    var id: String { taskID ?? "new" }
}

private enum CronDescription {
    static func describe(_ expression: String) -> String {
        let parts = expression.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return "Custom schedule" }
        if parts[0].hasPrefix("*/"), parts.dropFirst().allSatisfy({ $0 == "*" }) {
            return "Every \(parts[0].dropFirst(2)) minutes"
        }
        if let minute = Int(parts[0]), let hour = Int(parts[1]), parts[2] == "*", parts[3] == "*" {
            let time = String(format: "%02d:%02d", hour, minute)
            if parts[4] == "*" { return "Every day at \(time)" }
            let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            if let weekday = Int(parts[4]), days.indices.contains(weekday) {
                return "Every \(days[weekday]) at \(time)"
            }
        }
        return expression
    }
}

private extension ScheduledTask {
    static var preview: ScheduledTask {
        ScheduledTask(
            id: "daily-brief",
            agentId: "codex",
            channelId: "main",
            schedule: "0 9 * * 1",
            command: "Prepare a concise weekly project brief",
            enabled: true,
            createdAt: Date().addingTimeInterval(-86_400),
            updatedAt: Date().addingTimeInterval(-300)
        )
    }
}

#Preview("Scheduled Screen") {
    ScheduledTasksScreen(apiClient: SloppyAPIClient(baseURL: .debugURL))
        .frame(width: 1100, height: 720)
}

#Preview("Scheduled Row") {
    ScheduledTaskRow(task: .preview, agentName: "Codex")
        .frame(width: 380)
        .padding()
}

#Preview("Scheduled Detail") {
    ScheduledTaskDetail(
        task: .preview,
        agentName: "Codex",
        onEdit: {},
        onToggle: { _ in },
        onDelete: {}
    )
    .frame(width: 700, height: 560)
}

#Preview("Scheduled Editor") {
    ScheduledTaskEditor(
        draft: ScheduledTaskDraft(task: .preview),
        agents: [APIAgentRecord(id: "codex", displayName: "Codex")],
        onSave: { _ in }
    )
}
