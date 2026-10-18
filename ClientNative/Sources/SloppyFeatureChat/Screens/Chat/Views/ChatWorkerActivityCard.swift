import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct ChatWorkerSessionCard: View {
    let child: ChatSubSessionEvent
    let viewModel: ChatScreenViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        let worker = viewModel.parallelAgents.agents.first { $0.summary.id == child.childSessionId }
        Button {
            viewModel.openLongChatWorker(child.childSessionId)
        } label: {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                AgentBotAvatar(
                    agentID: viewModel.selectedAgent?.id ?? "worker", size: 40,
                    emotion: worker?.isWorking == true ? .working : .idle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.selectedAgent?.displayName ?? "Worker").font(.caption).foregroundStyle(.secondary)
                    Text(child.title).font(.headline)
                    Text(worker?.status ?? "Status unavailable").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(theme.spacing.m)
        }
        .buttonStyle(.plain)
        .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.colors.borderBold.opacity(0.6), lineWidth: 1))
        .accessibilityIdentifier("chat.worker.\(child.childSessionId)")
    }
}

@MainActor
struct ChatWorkerActivityCard: View {
    let viewModel: ChatScreenViewModel
    @Environment(\.theme) private var theme
    @State private var expanded = false

    var body: some View {
        let workers = viewModel.parallelAgents.agents
        let working = workers.filter(\.isWorking).count
        let waiting = workers.filter { $0.state == .waitingInput }.count
        let completed = workers.filter { $0.state == .completed }.count
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: theme.spacing.s) {
                    HStack(spacing: -8) {
                        ForEach(workers.prefix(4)) { worker in
                            AgentBotAvatar(agentID: worker.summary.agentId, size: 26)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workers · \(workers.count)").font(.callout.weight(.semibold))
                        Text("\(working) working · \(waiting) waiting · \(completed) completed")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }
            }.buttonStyle(.plain)
            if expanded {
                ForEach(workers) { worker in
                    ChatWorkerSessionCard(
                        child: .init(childSessionId: worker.summary.id, title: worker.summary.title),
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(theme.spacing.m)
        .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.colors.borderBold.opacity(0.6), lineWidth: 1))
        .accessibilityIdentifier("chat.worker-activity")
    }
}

#if os(macOS)
/// Workers remain discoverable without taking permanent space from the composer.
@MainActor
public struct ChatWorkerActivityPanel: View {
    let workers: [ChatParallelAgent]
    let onOpenWorker: @MainActor (String) -> Void
    @State private var isExpanded = false
    @Environment(\.theme) private var theme

    public init(workers: [ChatParallelAgent], onOpenWorker: @escaping @MainActor (String) -> Void) {
        self.workers = workers
        self.onOpenWorker = onOpenWorker
    }

    public var body: some View {
        let active = workers.filter { $0.isWorking || $0.state == .waitingInput }.count
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Workers · \(workers.count)").font(.callout.weight(.medium))
                            .foregroundStyle(theme.colors.textSecondary)
                        Text(active == 0 ? "No active workers" : "\(active) active")
                            .font(.caption).foregroundStyle(theme.colors.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(theme.colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.worker-activity.toggle")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workers) { worker in
                        Button { onOpenWorker(worker.summary.id) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                AgentBotAvatar(agentID: worker.summary.agentId, size: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(worker.summary.title).lineLimit(2)
                                        .foregroundStyle(theme.colors.textPrimary)
                                    Text(worker.status).font(.caption)
                                        .foregroundStyle(theme.colors.textMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2)
                                    .foregroundStyle(theme.colors.textMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.worker.\(worker.summary.id)")
                    }
                }
                .padding(.top, 8)
            }
        }
        .tint(theme.colors.textMuted)
        .padding(14)
        .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.worker-activity")
    }
}
#endif
