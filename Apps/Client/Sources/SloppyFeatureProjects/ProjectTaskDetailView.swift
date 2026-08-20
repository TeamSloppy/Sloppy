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
struct ProjectTaskDetailView: View {
    let projectId: String
    let task: APIProjectTask
    let apiClient: SloppyAPIClient

    @Environment(\.theme) private var theme
    @State private var comments: [APITaskComment] = []
    @State private var commentDraft = ""
    @State private var statusText = ""
    @State private var isLoading = false

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
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
                    Button("SEND COMMENT") { submitComment() }
                        .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .foregroundColor(c.accent)
                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.system(size: ty.micro))
                            .foregroundColor(c.textMuted)
                    }
                }
            }
            .padding(sp.l)
        }
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
