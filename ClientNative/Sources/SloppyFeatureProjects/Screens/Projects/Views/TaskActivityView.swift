import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct TaskActivityView: View {
    let model: TaskActivityViewModel
    let projectId: String
    let task: APIProjectTask
    let projectTasks: [APIProjectTask]
    var onOpenRelated: (@MainActor (APIProjectTask) -> Void)? = nil
    var onReviewChanged: @MainActor () async -> Void = {}
    @State private var tab: TaskActivityTab = .comments
    @State private var query = ""
    @State private var newestFirst = true
    @State private var commentDraft = ""
    @State private var visibleComments: [TaskComment] = []
    @State private var refreshID = 0
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(TaskActivityTab.allCases) { item in
                        Button { tab = item } label: {
                            Text(item.title).font(.callout.weight(tab == item ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(tab == item ? theme.colors.surfaceRaised : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tab == item ? theme.colors.accentCyan : theme.colors.textSecondary)
                        .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                    }
                }
            }
            HStack {
                Text(tab.title).font(.headline)
                Spacer()
                Button { refreshID &+= 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.isLoading).accessibilityLabel("Refresh task activity")
            }
            if let error = model.actionError {
                Text(error).font(.callout).foregroundStyle(theme.colors.statusBlocked)
            }
            if model.isLoading && !model.hasLoaded(tab) {
                LoadingSkeleton("Loading \(tab.title.lowercased())…").frame(height: 360).clipped()
            } else if let error = model.errorMessage, !model.hasLoaded(tab) {
                Text(error).font(.callout).foregroundStyle(theme.colors.statusBlocked)
                Button("Retry") { refreshID &+= 1 }
            } else {
                if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked) }
                tabContent
            }
        }
        .task(id: "\(projectId):\(task.id):\(tab.rawValue):\(refreshID)") {
            await model.load(tab, projectId: projectId, taskId: task.id, force: refreshID > 0)
        }
        .task(id: "\(tab.rawValue):\(query):\(newestFirst):\(model.revision)") {
            let comments = model.comments
            let technical = tab == .technical
            let query = query
            let newestFirst = newestFirst
            do {
                let result = try await ClientBackgroundWork.run {
                    TaskActivityViewModel.filterComments(comments, technical: technical, query: query, newestFirst: newestFirst)
                }
                guard !Task.isCancelled else { return }
                visibleComments = result
            } catch { }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .comments, .technical:
            if tab == .comments {
                TextField("Write a comment…", text: $commentDraft, axis: .vertical)
                    .lineLimit(3...6)
                    .taskActivityGlassField()
                Button(model.isSubmitting ? "Sending…" : "Comment") {
                    Task { if await model.addComment(commentDraft, projectId: projectId, taskId: task.id) { commentDraft = "" } }
                }
                .disabled(model.isSubmitting || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text("Worker events, retries, tool status and service messages.")
                    .font(.caption).foregroundStyle(theme.colors.textMuted)
            }
            HStack {
                TextField("Search comments or author", text: $query)
                    .taskActivityGlassField()
                Button(newestFirst ? "Newest first" : "Oldest first") { newestFirst.toggle() }.font(.caption)
            }
            Text("\(visibleComments.count) comments").font(.caption).foregroundStyle(theme.colors.textMuted)
            LazyVStack(spacing: 10) {
                ForEach(visibleComments) { comment in TaskCommentRow(comment: comment) }
            }
            if visibleComments.isEmpty { empty("No matching comments.") }
        case .history:
            StatusBadge.forTaskStatus(task.status)
            if let created = task.createdAt { Text("Created \(created.formatted())").font(.caption) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.activities) { activity in
                    VStack(alignment: .leading, spacing: 6) {
                        eventHeader(activity.field.capitalized, author: activity.actorId, date: activity.createdAt)
                        Text("\(activity.oldValue ?? "—") → \(activity.newValue ?? "—")")
                            .font(.callout).textSelection(.enabled)
                    }.activityCard(theme)
                }
            }
            if model.activities.isEmpty { empty("No changes recorded.") }
        case .logs:
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.logs) { log in
                    DisclosureGroup {
                        Text(log.message ?? "No message").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        if log.field != nil { Text("\(log.oldValue ?? "—") → \(log.newValue ?? "—")").font(.caption) }
                        if let worker = log.workerId { Text("Worker: \(worker)").font(.caption) }
                        if let channel = log.channelId { Text("Channel: \(channel)").font(.caption) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            eventHeader(log.title, author: log.agentId ?? log.actorId ?? "System", date: log.createdAt)
                            Text([log.kind, log.tool, log.ok.map { $0 ? "Succeeded" : "Failed" }, log.durationMs.map { "\($0) ms" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(log.ok == false ? theme.colors.statusBlocked : theme.colors.textMuted)
                        }
                    }.activityCard(theme)
                }
            }
            if model.logs.isEmpty { empty("No task logs yet.") }
        case .related:
            TaskRelatedActivityView(task: task, projectTasks: projectTasks, onOpen: onOpenRelated)
        case .review:
            TaskReviewActivityView(model: model, projectId: projectId, task: task, onChanged: onReviewChanged)
        case .clarifications:
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.clarifications) { item in
                    TaskClarificationActivityView(item: item, submitting: model.isSubmitting) { selected, note in
                        await model.answer(item, selected: selected, note: note, projectId: projectId, taskId: task.id)
                    }
                }
            }
            if model.clarifications.isEmpty { empty("No clarification requests.") }
        }
    }

    private func empty(_ title: String) -> some View {
        Text(title).font(.callout).foregroundStyle(theme.colors.textMuted).padding(.vertical, 16)
    }

    private func eventHeader(_ title: String, author: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            Text("\(author) · \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(theme.colors.textMuted)
        }
    }
}

extension View {
    func taskActivityGlassField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .backportGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func activityCard(_ theme: Theme) -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}
