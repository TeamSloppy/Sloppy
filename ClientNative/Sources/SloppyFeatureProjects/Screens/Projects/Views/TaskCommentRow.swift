import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct TaskCommentRow: View {
    let comment: TaskComment
    @State private var expanded = false
    @State private var showSource = false
    @Environment(\.theme) private var theme

    private var author: String { comment.sourceAuthor?.isEmpty == false ? comment.sourceAuthor! : comment.authorActorId }
    private var isLong: Bool { comment.content.count > 650 || comment.content.filter { $0 == "\n" }.count > 8 }
    private var kindTitle: String {
        switch comment.effectiveKind {
        case "user_comment": comment.isAgentReply ? "Agent reply" : "Comment"
        case "result": "Result"
        case "action_required": "Action required"
        case "technical": "Technical"
        default: comment.effectiveKind
        }
    }
    private var kindColor: Color {
        switch comment.effectiveKind {
        case "result": theme.colors.statusDone
        case "action_required": theme.colors.statusWarning
        case "technical": theme.colors.textSecondary
        default: theme.colors.accentCyan
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(author.prefix(2)).uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(kindColor)
                    .frame(width: 30, height: 30)
                    .background(kindColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(author).font(.callout.weight(.semibold))
                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(theme.colors.textMuted)
                }
                Spacer(minLength: 4)
                Menu {
                    Button(showSource ? "Formatted text" : "View source") { showSource.toggle() }
                } label: { Image(systemName: "ellipsis") }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
                .accessibilityLabel("Comment display options")
            }
            TaskChipFlowLayout {
                TaskMetadataChip(title: kindTitle, icon: "text.bubble", color: kindColor)
                if let source = comment.externalMetadata?.providerId {
                    TaskMetadataChip(title: source, icon: "arrow.down.circle", color: theme.colors.accentCyan)
                } else if comment.sourceAuthor != nil {
                    TaskMetadataChip(title: "Imported", icon: "arrow.down.circle", color: theme.colors.accentCyan)
                }
                if let mention = comment.mentionedActorId {
                    TaskMetadataChip(title: mention, icon: "at", color: theme.colors.statusReady)
                }
            }
            Group {
                if showSource {
                    Text(comment.content).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                } else {
                    TaskMarkdownView(text: comment.content)
                }
            }
            .frame(maxHeight: isLong && !expanded ? 170 : nil, alignment: .topLeading)
            .clipped()
            if isLong {
                Button(expanded ? "Show less" : "Show full comment") { expanded.toggle() }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(theme.colors.accentCyan)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surfaceRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.colors.border, lineWidth: 1))
    }
}
