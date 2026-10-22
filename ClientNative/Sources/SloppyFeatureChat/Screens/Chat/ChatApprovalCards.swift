import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import UniformTypeIdentifiers
#if canImport(PhotosUI) && !os(macOS)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
struct ChatToolApprovalCard: View {
    let approval: PendingToolApprovalRecord
    let isResolving: Bool
    let errorMessage: String?
    let decide: @MainActor (Bool, ClientToolApprovalDecisionScope) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.s) {
                    approvalSummary
                    Spacer(minLength: theme.spacing.s)
                    approvalActions
                }
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    approvalSummary
                    ViewThatFits(in: .horizontal) {
                        approvalActions
                        VStack(alignment: .trailing, spacing: theme.spacing.s) {
                            persistentActions
                            singleCallActions
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusBlocked)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .background(theme.colors.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.colors.statusWarning.opacity(0.5), lineWidth: 1)
        }
        .disabled(isResolving)
        .accessibilityIdentifier("chat.tool-approval")
    }

    private var approvalSummary: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(theme.colors.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Action required")
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                Text(summary)
                    .font(.system(size: theme.typography.caption))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var approvalActions: some View {
        if isResolving {
            ProgressView()
                .controlSize(.small)
        } else {
            HStack(spacing: theme.spacing.s) {
                persistentActions
                singleCallActions
            }
            .fixedSize()
        }
    }

    private var persistentActions: some View {
        HStack(spacing: theme.spacing.s) {
            Button("Always Allow") {
                decide(true, .always)
            }
            .help("Save this permission for this agent across sessions.")
            .accessibilityIdentifier("chat.tool-approval.always")
            Button("Allow for this Session") {
                decide(true, .session)
            }
            .help("Allow this permission for the current chat session.")
            .accessibilityIdentifier("chat.tool-approval.session")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var singleCallActions: some View {
        HStack(spacing: theme.spacing.s) {
            Button("Deny", role: .destructive) {
                decide(false, .once)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("chat.tool-approval.deny")
            Button("Allow") {
                decide(true, .once)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("chat.tool-approval.once")
        }
        .controlSize(.small)
    }

    private var summary: String {
        let reason = approval.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty {
            return reason
        }
        if let tool = approval.tool, !tool.isEmpty {
            return "Allow \(tool) to continue this chat."
        }
        return "The agent is waiting for your approval."
    }
}

@MainActor
struct ChatQueuedMessagesCard: View {
    let messages: [ChatQueuedMessage]
    let cancel: @MainActor (UUID) -> Void

    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 44

    var body: some View {
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Label(
                    messages.count == 1 ? "Message queued" : "\(messages.count) messages queued",
                    systemImage: "clock"
                )
                .font(.system(size: theme.typography.caption))
                .foregroundStyle(theme.colors.textSecondary)
                .help("Sent in order after the current turn finishes")
                .accessibilityHint("Sent in order after the current turn finishes")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if index > 0 {
                                Rectangle()
                                    .fill(theme.colors.border)
                                    .frame(height: 1)
                            }
                            HStack(spacing: theme.spacing.s) {
                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .fixedSize()
                                Text(message.displayText)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help(message.displayText)
                                if !message.attachments.isEmpty {
                                    Label("\(message.attachments.count)", systemImage: "paperclip")
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .fixedSize()
                                        .accessibilityLabel("\(message.attachments.count) attachments")
                                }
                                Button {
                                    cancel(message.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Remove queued message")
                                .accessibilityLabel("Remove queued message \(index + 1)")
                                .accessibilityIdentifier("chat.message-queue.remove.\(message.id)")
                            }
                            .font(.system(size: theme.typography.caption))
                            .frame(height: max(44, rowHeight))
                        }
                    }
                }
                .frame(height: max(44, rowHeight) * CGFloat(min(messages.count, 3))
                       + CGFloat(max(0, min(messages.count, 3) - 1)))
            }
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.leading, theme.spacing.s)
            .padding(.trailing, theme.spacing.xs)
            .padding(.vertical, theme.spacing.s)
            .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.colors.border, lineWidth: theme.borders.thin)
            }
            .accessibilityIdentifier("chat.message-queue")
        }
    }
}
