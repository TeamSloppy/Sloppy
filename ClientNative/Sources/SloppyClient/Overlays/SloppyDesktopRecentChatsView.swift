#if os(macOS)
import SloppyClientUI
import SwiftUI

@MainActor
struct SloppyDesktopRecentChatsView: View {
    let state: SloppyDesktopOverlayState
    var rootLimit: Int? = nil

    var body: some View {
        VStack(spacing: 10) {
            ForEach(state.recentChatRows(rootLimit: rootLimit)) { row in
                HStack(spacing: 8) {
                    Button { state.openRecentChat(row.chat) } label: {
                        HStack(spacing: 9) {
                            if row.depth == 0 {
                                AgentBotAvatar(agentID: row.chat.agentID, size: 34,
                                    paletteID: state.agentPalettes[row.chat.agentID],
                                    emotion: state.agentEmotion(for: row.chat.agentID), isAnimated: state.isExpanded)
                            } else {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .frame(width: 18)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.chat.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text([row.chat.agentName, row.chat.projectName].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if row.subagentCount == 0 {
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open chat with \(row.chat.agentName)")
                    .accessibilityIdentifier("notch.session.\(row.id)")

                    if row.subagentCount > 0 {
                        Button { state.toggleRecentChatGroup(row.id) } label: {
                            HStack(spacing: 5) {
                                Label("\(row.subagentCount)", systemImage: "arrow.triangle.branch").monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                            }
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .frame(minWidth: 36, minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(row.subagentCount) subagent chats")
                        .accessibilityLabel("\(row.isExpanded ? "Hide" : "Show") \(row.subagentCount) subagent chats in \(row.chat.title)")
                        .accessibilityValue(row.isExpanded ? "Expanded" : "Collapsed")
                        .accessibilityIdentifier("notch.session.\(row.id).subagents")
                    }
                }
                .padding(.leading, CGFloat(min(row.depth, 4)) * 18)
            }
        }
    }
}
#endif
