import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct TaskRelatedActivityView: View {
    let task: APIProjectTask
    let projectTasks: [APIProjectTask]
    var onOpen: (@MainActor (APIProjectTask) -> Void)? = nil
    @Environment(\.theme) private var theme

    private var relationships: [(String, String)] {
        var items: [(String, String)] = []
        if let parent = task.parentTaskId { items.append((parent, "Parent")) }
        items += (task.dependsOnTaskIds ?? []).map { ($0, "Depends on") }
        items += projectTasks.filter { $0.parentTaskId == task.id }.map { ($0.id, "Subtask") }
        items += projectTasks.filter { $0.dependsOnTaskIds?.contains(task.id) == true }.map { ($0.id, "Blocks") }
        return items
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if relationships.isEmpty { Text("No related tasks.").foregroundStyle(theme.colors.textMuted) }
            ForEach(Array(relationships.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(entry.1) · \(entry.0)").font(.caption).foregroundStyle(theme.colors.accentCyan)
                    if let related = projectTasks.first(where: { $0.id == entry.0 }) {
                        if let onOpen {
                            Button(related.title) { onOpen(related) }.buttonStyle(.plain).font(.callout).foregroundStyle(theme.colors.accentCyan)
                        } else { Text(related.title).font(.callout) }
                        StatusBadge.forTaskStatus(related.status)
                    } else { Text("Task details are not in the loaded project.").font(.caption) }
                }.activityCard(theme)
            }
        }
    }
}

struct TaskReviewActivityView: View {
    let model: TaskActivityViewModel
    let projectId: String
    let task: APIProjectTask
    let onChanged: @MainActor () async -> Void
    @State private var reason = ""
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if task.status == "needs_review" {
                TextField("Reason for requesting changes…", text: $reason, axis: .vertical).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Approve") { Task { if await model.decideReview(approve: true, reason: "", projectId: projectId, taskId: task.id) { await onChanged() } } }
                    Button("Request changes") { Task { if await model.decideReview(approve: false, reason: reason, projectId: projectId, taskId: task.id) { await onChanged() } } }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.disabled(model.isSubmitting)
            }
            if let notice = model.reviewNotice {
                Text(notice).font(.callout).foregroundStyle(theme.colors.textMuted)
            }
            if let diff = model.diff {
                Text("\(diff.branchName) → \(diff.baseBranch)").font(.caption).textSelection(.enabled)
                if diff.hasChanges {
                    DisclosureGroup("Changes · \(model.diffLines.count) lines") {
                        ScrollView(.horizontal) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(model.diffLines.enumerated()), id: \.offset) { _, line in
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(line.hasPrefix("+") ? theme.colors.statusDone : line.hasPrefix("-") ? theme.colors.statusBlocked : theme.colors.textSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                } else { Text("No working-tree changes.").font(.callout) }
            }
            Text("Review comments · \(model.reviewComments.count)").font(.headline)
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.reviewComments) { comment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(comment.filePath)\(comment.lineNumber.map { ":\($0)" } ?? "")").font(.caption).foregroundStyle(theme.colors.accentCyan)
                        Text("\(comment.author) · \(comment.resolved ? "Resolved" : "Open") · \(comment.createdAt.formatted())")
                            .font(.caption).foregroundStyle(theme.colors.textMuted)
                        TaskMarkdownView(text: comment.content)
                        Button(comment.resolved ? "Reopen" : "Resolve") {
                            Task { await model.resolveReviewComment(comment, projectId: projectId, taskId: task.id) }
                        }.disabled(model.isSubmitting)
                    }.activityCard(theme)
                }
            }
            if model.reviewComments.isEmpty { Text("No review comments.").font(.callout).foregroundStyle(theme.colors.textMuted) }
        }
    }
}

struct TaskClarificationActivityView: View {
    let item: APITaskClarification
    let submitting: Bool
    let onAnswer: @MainActor ([String], String) async -> Void
    @State private var selected: String?
    @State private var note = ""
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskMetadataChip(title: item.status, icon: "questionmark.bubble", color: item.status == "pending" ? theme.colors.statusWarning : theme.colors.statusDone)
            Text("\(item.targetType) · \(item.createdAt.formatted())").font(.caption).foregroundStyle(theme.colors.textMuted)
            TaskMarkdownView(text: item.questionText)
            ForEach(item.options) { option in
                Button {
                    selected = selected == option.id ? nil : option.id
                } label: {
                    Label(option.label, systemImage: (item.status == "pending" ? selected == option.id : item.selectedOptionIds.contains(option.id)) ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(item.status != "pending" || submitting)
            }
            if item.status == "pending" {
                if item.allowNote { TextField("Add a note…", text: $note, axis: .vertical).textFieldStyle(.roundedBorder) }
                Button("Send answer") { Task { await onAnswer(selected.map { [$0] } ?? [], note) } }
                    .disabled(submitting || (selected == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            } else if let note = item.note, !note.isEmpty {
                TaskMarkdownView(text: note)
            }
        }.activityCard(theme)
    }
}
