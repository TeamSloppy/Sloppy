import AdaEngine
import Foundation
import SloppyClientCore
import SloppyClientUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public struct ProjectTaskDetailView: View {
    let projectId: String
    @State private var task: APIProjectTask
    let apiClient: SloppyAPIClient
    private let onTaskChanged: ((APIProjectRecord) -> Void)?

    @Environment(\.theme) private var theme
    @State private var comments: [APITaskComment] = []
    @State private var commentDraft = ""
    @State private var statusText = ""
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var isSaving = false

    public init(projectId: String, task: APIProjectTask, apiClient: SloppyAPIClient, onTaskChanged: ((APIProjectRecord) -> Void)? = nil) {
        self.projectId = projectId
        _task = State(initialValue: task)
        self.apiClient = apiClient
        self.onTaskChanged = onTaskChanged
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
                HStack {
                    Text(task.externalMetadata?.externalIssueKey ?? task.id).font(.system(size: 12)).foregroundColor(c.textMuted)
                    Spacer()
                    Button(isEditing ? "Close editor" : "Edit properties") { isEditing.toggle() }
                        .accessibilityIdentifier("task-detail-edit-properties")
                }
                if !statusText.isEmpty {
                    Text(statusText).font(.system(size: 12)).foregroundColor(c.textSecondary)
                }
                if isEditing {
                    ProjectTaskProperties(task: task, isSaving: isSaving, onSave: saveProperties, onCancel: { isEditing = false })
                }
                VStack(alignment: .leading, spacing: sp.s) {
                    Text(task.title)
                        .font(.system(size: ty.title))
                        .foregroundColor(c.textPrimary)
                    HStack(spacing: sp.s) {
                        StatusBadge.forTaskStatus(task.status)
                        if let external = task.externalMetadata?.externalStatus?.display {
                            Text("STARTTRACK: \(external.uppercased())")
                                .font(.system(size: ty.micro))
                                .foregroundColor(c.accent)
                        }
                    }
                    if let priority = task.priority {
                        Text("Priority: \(priority.capitalized)").font(.system(size: ty.caption))
                    }
                    if let actor = task.actorId {
                        Text("Agent: \(actor)").font(.system(size: ty.caption))
                    }
                    if let tags = task.tags, !tags.isEmpty {
                        Text(tags.joined(separator: " · ")).font(.system(size: ty.caption)).foregroundColor(c.accentCyan)
                    }
                    if let key = task.externalMetadata?.externalIssueKey {
                        Text(key)
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textMuted)
                    }
                    if let assignee = task.externalMetadata?.externalAssignee {
                        Text("Assignee: \(assignee)")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textSecondary)
                    }
                    if let priority = task.externalMetadata?.externalPriority {
                        Text("Priority: \(priority)")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textSecondary)
                    }
                    if let description = task.description, !description.isEmpty {
                        Text(markdown: description)
                            .textSelection(.enabled)
                            .font(.system(size: ty.body))
                            .foregroundColor(c.textSecondary)
                        ForEach(externalLinks(in: description), id: \.self) { link in
                            Button("OPEN LINK") { openExternalURL(link) }
                                .foregroundColor(c.accent)
                        }
                    }
                    if let url = task.externalMetadata?.externalIssueURL {
                        Button("OPEN IN STARTTRACK") { openExternalURL(url) }
                            .foregroundColor(c.accent)
                    }
                }

                ProjectTaskActivityView(projectID: projectId, taskID: task.id, api: apiClient)

                VStack(alignment: .leading, spacing: sp.s) {
                    Text("COMMENTS")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textMuted)
                    if comments.isEmpty && !isLoading {
                        EmptyStateView("No comments")
                    }
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: sp.xs) {
                            Text(comment.sourceAuthor ?? comment.authorActorId)
                                .font(.system(size: ty.micro))
                                .foregroundColor(comment.externalMetadata?.origin == "startrek" ? c.accent : c.textMuted)
                            Text(markdown: comment.content)
                                .textSelection(.enabled)
                                .font(.system(size: ty.body))
                                .foregroundColor(c.textPrimary)
                            ForEach(externalLinks(in: comment.content), id: \.self) { link in
                                Button("OPEN LINK") { openExternalURL(link) }
                                    .foregroundColor(c.accent)
                            }
                        }
                        .padding(sp.m)
                        .background(c.surface)
                    }
                    TextField("Add a comment", text: $commentDraft)
                        .font(.system(size: 14)).padding(8).frame(height: 42).background(c.surfaceRaised)
                        .accessibilityIdentifier("task-detail-comment")
                    Button("Send comment") { submitComment() }
                        .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .foregroundColor(c.accent)
                }
            }
            .padding(sp.l)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .sloppyTextInputStyle(theme.colors)
        .navigationTitle(task.externalMetadata?.externalIssueKey ?? task.id)
        .navigationTitlePosition(.leading)
        .onAppear { loadComments() }
    }

    private func loadComments() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                comments = try await apiClient.fetchTaskComments(projectId: projectId, taskId: task.id)
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func saveProperties(_ request: APIProjectTaskUpdateRequest) {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let project = try await apiClient.updateProjectTask(projectId: projectId, taskId: task.id, request: request)
                if let updated = project.tasks?.first(where: { $0.id == task.id }) { task = updated }
                onTaskChanged?(project)
                isEditing = false
                statusText = "Properties saved"
            } catch { statusText = error.localizedDescription }
        }
    }

    private func submitComment() {
        let content = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let comment = try await apiClient.addTaskComment(projectId: projectId, taskId: task.id, content: content)
                comments.append(comment)
                commentDraft = ""
                statusText = "Comment sent"
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func openExternalURL(_ rawValue: String) {
        guard let url = URL(string: rawValue), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        _ = Application.shared?.openURL(url)
        #endif
    }

    private func externalLinks(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s\)\]]+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
