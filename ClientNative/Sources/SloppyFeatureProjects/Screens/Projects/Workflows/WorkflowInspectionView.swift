import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct WorkflowInspectionView: View {
    let node: ProjectWorkflowNode?
    let workflow: ProjectWorkflow?
    let steps: [ProjectWorkflowRunStep]
    let showsDefinition: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showsDefinition, let node {
                        Text(ProjectWorkflowFormatting.title(node.type)).foregroundStyle(.secondary)
                        if let lane = workflow?.lanes.first(where: { $0.id == node.laneId }) {
                            LabeledContent("Lane", value: lane.title)
                            if let actor = lane.actorId { LabeledContent("Agent", value: actor) }
                            if let team = lane.teamId { LabeledContent("Team", value: team) }
                        }
                        jsonDisclosure("Configuration", value: node.config)
                        let edges = workflow?.edges.filter { $0.sourceNodeId == node.id } ?? []
                        if !edges.isEmpty {
                            Text("Next steps").font(.headline)
                            ForEach(edges) { edge in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(workflow?.nodes.first { $0.id == edge.targetNodeId }?.title ?? edge.targetNodeId,
                                          systemImage: "arrow.right")
                                    if let label = edge.label { Text(label).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    ForEach(steps) { step in
                        Divider()
                        WorkflowStatusLabel(status: step.status)
                        LabeledContent("Started") { Text(step.startedAt, format: .dateTime) }
                        if let finished = step.finishedAt {
                            LabeledContent("Finished") { Text(finished, format: .dateTime) }
                        }
                        if let error = step.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        jsonDisclosure("Input", value: step.input)
                        jsonDisclosure("Output", value: step.output)
                    }
                }
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(showsDefinition ? (node?.title ?? "Step") : (steps.first?.nodeId ?? "Step"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 440, idealHeight: 640)
        #endif
        .accessibilityIdentifier("workflow-inspection")
    }

    private func jsonDisclosure(_ title: String, value: [String: ProjectWorkflowJSONValue]) -> some View {
        DisclosureGroup(title) {
            Text(ProjectWorkflowFormatting.json(value))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }
}
