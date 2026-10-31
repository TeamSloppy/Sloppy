import SwiftUI
import SloppyClientCore
import SloppyClientUI

/// A deterministic topology layout also works for agent-created nodes without saved positions.
struct ProjectWorkflowGraphLayout {
    static let nodeSize = CGSize(width: 232, height: 132)
    let positions: [String: CGPoint]
    let size: CGSize

    init(workflow: ProjectWorkflow) {
        let ids = workflow.nodes.map(\.id)
        let known = Set(ids)
        let edges = workflow.edges.filter { known.contains($0.sourceNodeId) && known.contains($0.targetNodeId) }
        let outgoing = Dictionary(grouping: edges, by: \.sourceNodeId)
        var incoming = edges.reduce(into: [String: Int]()) { $0[$1.targetNodeId, default: 0] += 1 }
        var ranks: [String: Int] = [:]
        var queue = ids.filter { incoming[$0, default: 0] == 0 }
        var index = 0
        while index < queue.count {
            let id = queue[index]
            index += 1
            let rank = ranks[id, default: 0]
            ranks[id] = rank
            for edge in outgoing[id] ?? [] {
                ranks[edge.targetNodeId] = max(ranks[edge.targetNodeId, default: 0], rank + 1)
                incoming[edge.targetNodeId, default: 0] -= 1
                if incoming[edge.targetNodeId] == 0 { queue.append(edge.targetNodeId) }
            }
        }
        // Loops are legitimate workflow edges. Place their unvisited nodes without recursing.
        let visited = Set(queue)
        var nextRank = (ranks.values.max() ?? -1) + 1
        for id in ids where !visited.contains(id) {
            ranks[id] = nextRank
            nextRank += 1
        }
        var rows: [Int: Int] = [:]
        var positions: [String: CGPoint] = [:]
        for id in ids {
            let rank = ranks[id, default: 0]
            let row = rows[rank, default: 0]
            rows[rank] = row + 1
            positions[id] = CGPoint(x: 32 + CGFloat(rank) * 342, y: 48 + CGFloat(row) * 184)
        }
        self.positions = positions
        size = CGSize(
            width: (positions.values.map(\.x).max() ?? 0) + Self.nodeSize.width + 32,
            height: (positions.values.map(\.y).max() ?? 0) + Self.nodeSize.height + 48
        )
    }
}

struct ProjectWorkflowGraph: View {
    let workflow: ProjectWorkflow
    let detail: ProjectWorkflowRunDetail?
    let onSelect: (ProjectWorkflowNode) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let layout = ProjectWorkflowGraphLayout(workflow: workflow)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in workflow.edges {
                        guard let source = layout.positions[edge.sourceNodeId],
                              let target = layout.positions[edge.targetNodeId] else { continue }
                        let start = CGPoint(x: source.x + ProjectWorkflowGraphLayout.nodeSize.width, y: source.y + 66)
                        let end = CGPoint(x: target.x, y: target.y + 66)
                        var path = Path()
                        path.move(to: start)
                        let bend = max(45, abs(end.x - start.x) / 2)
                        path.addCurve(to: end,
                                      control1: CGPoint(x: start.x + bend, y: start.y),
                                      control2: CGPoint(x: end.x - bend, y: end.y))
                        context.stroke(path, with: .color(theme.colors.textMuted), lineWidth: 1.5)
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: end.x - 7, y: end.y - 4))
                        arrow.addLine(to: end)
                        arrow.addLine(to: CGPoint(x: end.x - 7, y: end.y + 4))
                        context.stroke(arrow, with: .color(theme.colors.textMuted), lineWidth: 1.5)
                        if let label = edge.label, !label.isEmpty {
                            context.draw(Text(label).font(.caption2).foregroundColor(theme.colors.textSecondary),
                                         at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 12))
                        }
                    }
                }
                .accessibilityHidden(true)

                ForEach(workflow.nodes) { node in
                    if let position = layout.positions[node.id] {
                        Button { onSelect(node) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(ProjectWorkflowFormatting.title(node.type)).font(.caption)
                                    Spacer(minLength: 0)
                                    if let status = status(for: node.id) {
                                        WorkflowStatusLabel(status: status)
                                    }
                                }
                                Text(node.title).font(.headline).lineLimit(2)
                                    .foregroundStyle(theme.colors.textPrimary)
                                if let lane = workflow.lanes.first(where: { $0.id == node.laneId }) {
                                    Text(lane.title).font(.caption).lineLimit(1)
                                }
                            }
                            .foregroundStyle(theme.colors.textSecondary)
                            .padding(14)
                            .frame(width: ProjectWorkflowGraphLayout.nodeSize.width,
                                   height: ProjectWorkflowGraphLayout.nodeSize.height, alignment: .topLeading)
                            .background(theme.colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isCurrent(node.id) ? theme.colors.textPrimary : theme.colors.border,
                                                  lineWidth: isCurrent(node.id) ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workflow-node-\(node.id)")
                        .offset(x: position.x, y: position.y)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
        }
        .accessibilityIdentifier("project-workflow-graph")
    }

    private func status(for nodeID: String) -> String? {
        guard let detail else { return nil }
        return detail.steps.filter { $0.nodeId == nodeID }.max { $0.startedAt < $1.startedAt }?.status
            ?? (isCurrent(nodeID) ? detail.run.status : "pending")
    }

    private func isCurrent(_ nodeID: String) -> Bool {
        detail?.run.currentNodeIds.contains(nodeID) == true
    }
}

struct WorkflowStatusLabel: View {
    let status: String
    @Environment(\.theme) private var theme

    var body: some View {
        Label(ProjectWorkflowFormatting.title(status), systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var icon: String {
        switch status {
        case "completed", "succeeded": "checkmark.circle"
        case "failed": "xmark.circle"
        case "running": "arrow.triangle.2.circlepath"
        case "waiting", "waiting_for_human", "waiting_for_agent", "waiting_for_workflow", "blocked": "pause.circle"
        case "cancelled", "skipped": "minus.circle"
        default: "clock"
        }
    }

    private var color: Color {
        switch status {
        case "completed", "succeeded": .green
        case "failed": .red
        case "waiting", "waiting_for_human", "waiting_for_agent", "waiting_for_workflow", "blocked": .orange
        default: theme.colors.textSecondary
        }
    }
}
