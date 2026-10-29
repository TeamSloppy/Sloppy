import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProjectTaskActivityView: View {
    let projectID: String
    let taskID: String
    let api: SloppyAPIClient
    @State private var section = "Activity"
    @State private var activities: [APITaskActivity] = []
    @State private var logs: [APITaskLog] = []
    @State private var questions: [APITaskClarification] = []
    @State private var diff: APITaskDiff?
    @State private var selectedOptions: [String: Set<String>] = [:]
    @State private var notes: [String: String] = [:]
    @State private var error: String?
    @State private var isLoading = false
    @State private var generation = 0
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(["Activity", "Logs", "Changes", "Questions"], id: \.self) { tab in
                    Button(tab) { section = tab; load() }.foregroundColor(section == tab ? theme.colors.textPrimary : theme.colors.textMuted)
                }
                Spacer()
                Button("Refresh", action: load)
            }.font(.system(size: 12)).frame(height: 36)
            if isLoading { Text("Loading…").font(.system(size: 12)) }
            if let error { Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked) }
            content
        }.onAppear { load() }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case "Activity":
            if activities.isEmpty && !isLoading && error == nil { Text("No activity yet").font(.system(size: 12)) }
            ForEach(activities) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.field): \(item.oldValue ?? "—") → \(item.newValue ?? "—")").textSelection(.enabled).font(.system(size: 13))
                    Text("\(item.actorId) · \(item.createdAt.formatted())").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                }.padding(10)
            }
        case "Logs":
            if logs.isEmpty && !isLoading && error == nil { Text("No task logs").font(.system(size: 12)) }
            ForEach(logs) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                    if let message = item.message { Text(message).textSelection(.enabled).font(.system(size: 12)) }
                    Text("\(item.kind) · \(item.createdAt.formatted())").font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                }.padding(10).background(theme.colors.surface)
            }
        case "Changes":
            if let diff {
                Text("\(diff.branchName) → \(diff.baseBranch)").font(.system(size: 12))
                Text(diff.hasChanges ? diff.diff : "No task changes").textSelection(.enabled).font(.system(size: 12))
            }
        default:
            if questions.isEmpty && !isLoading && error == nil { Text("No clarification questions").font(.system(size: 12)) }
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.questionText).textSelection(.enabled).font(.system(size: 14, weight: .semibold))
                    Text(question.status).font(.system(size: 11)).foregroundColor(theme.colors.textMuted)
                    ForEach(question.options) { option in
                        Button {
                            var ids = selectedOptions[question.id] ?? Set(question.selectedOptionIds)
                            if !ids.insert(option.id).inserted { ids.remove(option.id) }
                            selectedOptions[question.id] = ids
                        } label: {
                            Text("\((selectedOptions[question.id] ?? Set(question.selectedOptionIds)).contains(option.id) ? "●" : "○") \(option.label)")
                                .font(.system(size: 13)).padding(8)
                        }.disabled(question.answeredAt != nil || isLoading)
                    }
                    if question.allowNote {
                        TextField("Additional note", text: Binding(get: { notes[question.id] ?? question.note ?? "" }, set: { notes[question.id] = $0 }))
                            .disabled(question.answeredAt != nil)
                    }
                    if question.answeredAt == nil {
                        Button("Submit answer") { answer(question) }.disabled(isLoading || (selectedOptions[question.id] ?? []).isEmpty)
                    }
                }.padding(14).background(theme.colors.surface)
            }
        }
    }
    private func load() {
        generation += 1
        let current = generation
        let tab = section
        error = nil
        isLoading = true
        Task { @MainActor in
            defer { if current == generation { isLoading = false } }
            do {
                switch tab {
                case "Activity":
                    let result = try await api.workspace.taskActivities(projectID: projectID, taskID: taskID)
                    if current == generation { activities = result }
                case "Logs":
                    let result = try await api.workspace.taskLogs(projectID: projectID, taskID: taskID)
                    if current == generation { logs = result }
                case "Changes":
                    let result = try await api.workspace.taskDiff(projectID: projectID, taskID: taskID)
                    if current == generation { diff = result }
                default:
                    let result = try await api.workspace.taskClarifications(projectID: projectID, taskID: taskID)
                    if current == generation { questions = result }
                }
            } catch { if current == generation { self.error = error.localizedDescription } }
        }
    }
    private func answer(_ question: APITaskClarification) {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let result = try await api.workspace.answerTaskClarification(projectID: projectID, taskID: taskID, clarificationID: question.id,
                    answer: APITaskClarificationAnswer(selectedOptionIds: Array(selectedOptions[question.id] ?? []).sorted(), note: notes[question.id] ?? ""))
                if let index = questions.firstIndex(where: { $0.id == question.id }) { questions[index] = result }
            } catch { self.error = error.localizedDescription }
        }
    }
}
