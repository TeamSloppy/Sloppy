import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct PullRequestDetailView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case code = "Code"

        var id: Self { self }
    }

    let apiClient: SloppyAPIClient
    let item: CodeReviewItem
    let showsBackButton: Bool
    let onBack: @MainActor () -> Void
    let onOpenChat: @MainActor (CodeReviewDetail) -> Void
    let onAddToSideChat: @MainActor (String) -> Void
    let onResolveOpenIssues: @MainActor (String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var mode = Mode.summary
    @State private var detail: CodeReviewDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var focusedComment: CodeReviewComment?
    @State private var hoveredCommentID: String?
    @State private var replyingCommentID: String?
    @State private var replyDrafts: [String: String] = [:]
    @State private var postingReplyCommentIDs: Set<String> = []
    @State private var replyError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showsBackButton {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Back to pull requests")
            }

            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(stateColor)

            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)

            Button {
                if let url = URL(string: item.url) { openURL(url) }
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open pull request in browser")

            Button {
                if let detail { onOpenChat(detail) }
            } label: {
                Label("Open chat", systemImage: "bubble.left")
            }
            .buttonStyle(.bordered)
            .disabled(detail == nil)
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            LoadingSkeleton("Loading pull request…")
        } else if let detail {
            switch mode {
            case .summary:
                summary(detail)
            case .code:
                code(detail)
            }
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn’t Load Pull Request", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
                    .textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ detail: CodeReviewDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryHeader(detail)

                if let description = detail.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    reviewSection("Description") {
                        markdown(description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                reviewSection(
                    "Comments",
                    count: detail.comments.count,
                    actionTitle: "Resolve Opened Issues",
                    actionSystemImage: "sparkles",
                    actionDisabled: CodeReviewChatPromptBuilder.openComments(in: detail).isEmpty,
                    action: {
                        onResolveOpenIssues(CodeReviewChatPromptBuilder.promptForOpenIssues(in: detail))
                    }
                ) {
                    comments(detail)
                }

                if detail.diffTruncated {
                    Label(
                        "The code diff was truncated to keep review navigation responsive.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryHeader(_ detail: CodeReviewDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail.item.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle")
                Text(detail.item.author ?? "Unknown author")
                if let updatedAt = detail.item.updatedAt {
                    Text("·")
                    Text(updatedAt, format: .relative(presentation: .named))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                metadataRow(
                    "Branch",
                    systemImage: "arrow.triangle.branch",
                    value: branchTitle(detail)
                )
                metadataRow(
                    "Reviewers",
                    systemImage: "person.2",
                    value: detail.reviewers.isEmpty ? "No reviewers" : detail.reviewers.joined(separator: ", ")
                )
                metadataRow(
                    "Comments",
                    systemImage: "bubble.left.and.bubble.right",
                    value: "\(detail.comments.count) comments"
                )
                metadataRow(
                    "Checks",
                    systemImage: "checkmark.seal",
                    value: detail.item.checksStatus ?? "No CI checks"
                )
                metadataRow(
                    "Status",
                    systemImage: "circlebadge",
                    value: statusTitle(detail.item)
                )
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func comments(_ detail: CodeReviewDetail) -> some View {
        if let commentsError = detail.commentsError {
            Label(commentsError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, detail.comments.isEmpty ? 0 : 10)
        }

        if detail.comments.isEmpty {
            Text("No review comments")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(threadedComments(detail.comments)) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        commentCard(row.comment)
                        commentActions(row.comment)
                        if replyingCommentID == row.comment.id {
                            replyComposer(for: row.comment)
                        }
                    }
                    .padding(.leading, CGFloat(row.depth) * 26)
                    .overlay(alignment: .leading) {
                        if row.depth > 0 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.24))
                                .frame(width: 1)
                                .padding(.vertical, 8)
                                .padding(.leading, CGFloat(row.depth - 1) * 26 + 12)
                        }
                    }
                }
            }
        }
    }

    private func commentCard(_ comment: CodeReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            commentHeader(comment)

            if let filePath = comment.filePath {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text(filePath)
                    if let line = comment.line ?? comment.originalLine {
                        Text(":\(line)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Show in Code") {
                        focusedComment = comment
                        mode = .code
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }

            if let diffHunk = comment.diffHunk, !diffHunk.isEmpty {
                CodeReviewInlineDiffView(
                    diff: diffHunk,
                    filePath: comment.filePath ?? "Changes",
                    highlightedLine: comment.line ?? comment.originalLine
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }

            markdown(comment.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .textSelection(.enabled)
        }
        .background(Color.secondary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered in
            if isHovered {
                hoveredCommentID = comment.id
            } else if hoveredCommentID == comment.id {
                hoveredCommentID = nil
            }
        }
    }

    private func commentHeader(_ comment: CodeReviewComment) -> some View {
        let showsChatButton = showsCommentChatButton(comment.id)
        return HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.secondary)
            Text(comment.author ?? "Unknown reviewer")
                .font(.subheadline.weight(.semibold))

            if comment.isResolved == true {
                statusBadge("Resolved", color: .green)
            } else if comment.isOutdated == true {
                statusBadge("Outdated", color: .secondary)
            } else if let status = comment.status, !status.isEmpty {
                statusBadge(status.replacingOccurrences(of: "_", with: " ").capitalized, color: .orange)
            }

            Spacer(minLength: 8)

            Button { addCommentToSideChat(comment) } label: {
                Image(systemName: "plus.bubble")
            }
            .buttonStyle(.borderless)
            .opacity(showsChatButton ? Double(1) : Double(0))
            .allowsHitTesting(showsChatButton)
            .accessibilityHidden(!showsChatButton)
            .accessibilityLabel("Add comment to chat")
            .help("Add this comment to the side chat")

            if let createdAt = comment.createdAt {
                Text(createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(Color.secondary.opacity(0.055))
    }

    private func addCommentToSideChat(_ comment: CodeReviewComment) {
        guard let detail else { return }
        onAddToSideChat(CodeReviewChatPromptBuilder.prompt(for: comment, in: detail))
    }

    @ViewBuilder
    private func code(_ detail: CodeReviewDetail) -> some View {
        if let diffError = detail.diffError {
            ContentUnavailableView {
                Label("Couldn’t Load Code Diff", systemImage: "exclamationmark.triangle")
            } description: {
                Text(diffError).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CodeReviewSideBySideDiffView(
                diff: detail.diff,
                highlightedPath: focusedComment?.filePath,
                highlightedLine: focusedComment?.line ?? focusedComment?.originalLine,
                onAddToChat: { line in
                    onAddToSideChat(CodeReviewChatPromptBuilder.prompt(for: line, in: detail))
                }
            )
        }
    }

    private func commentActions(_ comment: CodeReviewComment) -> some View {
        HStack(spacing: 10) {
            if item.providerId == "arcadia-code-review" {
                Button(replyingCommentID == comment.id ? "Cancel reply" : "Reply") {
                    if replyingCommentID == comment.id {
                        replyingCommentID = nil
                    } else {
                        replyingCommentID = comment.id
                        replyError = nil
                    }
                }
                .buttonStyle(.borderless)
            }
            if let replyTo = comment.inReplyToId {
                Text("Reply to #\(replyTo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.leading, 4)
    }

    private func replyComposer(for comment: CodeReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: replyBinding(for: comment.id))
                .font(.callout)
                .frame(minHeight: 74, maxHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
                }
            if let replyError {
                Label(replyError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Send reply") { Task { await sendReply(to: comment) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        replyDrafts[comment.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || postingReplyCommentIDs.contains(comment.id)
                    )
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func replyBinding(for commentID: String) -> Binding<String> {
        Binding(
            get: { replyDrafts[commentID, default: ""] },
            set: { replyDrafts[commentID] = $0 }
        )
    }

    private func sendReply(to comment: CodeReviewComment) async {
        let body = replyDrafts[comment.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        postingReplyCommentIDs.insert(comment.id)
        defer { postingReplyCommentIDs.remove(comment.id) }
        do {
            var reply = try await apiClient.replyToCodeReviewComment(
                providerID: item.providerId,
                reviewID: item.id,
                parentCommentID: comment.id,
                body: body
            )
            if reply.inReplyToId == nil { reply.inReplyToId = comment.id }
            detail?.comments.append(reply)
            replyDrafts[comment.id] = ""
            replyingCommentID = nil
            replyError = nil
        } catch {
            replyError = error.localizedDescription
        }
    }

    private func threadedComments(_ comments: [CodeReviewComment]) -> [ThreadedComment] {
        let knownIDs = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments.filter { comment in
            guard let parentID = comment.inReplyToId else { return false }
            return knownIDs.contains(parentID)
        }, by: { $0.inReplyToId! })
        let roots = comments.filter { comment in
            guard let parentID = comment.inReplyToId else { return true }
            return !knownIDs.contains(parentID)
        }
        var rows: [ThreadedComment] = []
        func append(_ comment: CodeReviewComment, depth: Int) {
            rows.append(ThreadedComment(comment: comment, depth: depth))
            for child in children[comment.id] ?? [] {
                append(child, depth: depth + 1)
            }
        }
        for root in roots { append(root, depth: 0) }
        return rows
    }

    private func reviewSection<Content: View>(
        _ title: String,
        count: Int? = nil,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        actionDisabled: Bool = false,
        action: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 8)
                if let actionTitle, let action {
                    Button(action: action) {
                        if let actionSystemImage {
                            Label(actionTitle, systemImage: actionSystemImage)
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(actionDisabled)
                }
            }
            Divider()
            content()
        }
    }

    private func metadataRow(_ title: String, systemImage: String, value: String) -> some View {
        GridRow {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 105, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func markdown(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value) {
            return Text(attributed)
        }
        return Text(value)
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func showsCommentChatButton(_ commentID: String) -> Bool {
#if os(macOS)
        hoveredCommentID == commentID
#else
        true
#endif
    }

    private func branchTitle(_ detail: CodeReviewDetail) -> String {
        let source = detail.sourceBranch ?? "head"
        let target = detail.targetBranch ?? "base"
        return "\(source)  →  \(target)"
    }

    private func statusTitle(_ item: CodeReviewItem) -> String {
        if item.isDraft { return "Draft" }
        if let decision = item.reviewDecision, !decision.isEmpty {
            return decision.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return switch item.state {
        case .open, .all: "Ready for review"
        case .closed: "Closed"
        case .merged: "Merged"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .open, .all: .green
        case .closed: .red
        case .merged: .purple
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await apiClient.fetchCodeReviewDetail(
                providerID: item.providerId,
                reviewID: item.id
            )
            errorMessage = nil
        } catch {
            detail = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct ThreadedComment: Identifiable {
    let comment: CodeReviewComment
    let depth: Int

    var id: String { comment.id }
}
