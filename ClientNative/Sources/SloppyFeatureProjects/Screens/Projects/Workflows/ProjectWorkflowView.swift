import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ProjectWorkflowView: View {
    let viewModel: ProjectWorkflowViewModel
    let projectId: String
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsGraph = true
    @State private var inspection: WorkflowInspection?

    public init(viewModel: ProjectWorkflowViewModel, projectId: String) {
        self.viewModel = viewModel
        self.projectId = projectId
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            if let error = viewModel.detailErrorMessage {
                errorBanner(error)
            }
            if let workflow = viewModel.selectedWorkflow {
                workflowContent(workflow)
            } else if viewModel.isLoading {
                ProgressView("Loading workflows…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    viewModel.errorMessage == nil ? "No workflows yet" : "Workflows unavailable",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(viewModel.errorMessage == nil
                        ? "Workflows created by your agents for this project appear here."
                        : "Refresh to try loading this project's workflows again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.background)
        .task(id: projectId) { await poll() }
        .sheet(item: $inspection) { item in
            WorkflowInspectionView(
                node: viewModel.selectedWorkflow?.nodes.first { $0.id == item.nodeID },
                workflow: viewModel.selectedWorkflow,
                steps: inspectionSteps(item),
                showsDefinition: item.stepID == nil || viewModel.canOverlayRun
            )
        }
        .accessibilityIdentifier("project-workflows")
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { selectors; Spacer(minLength: 0); displayControls }
            VStack(alignment: .leading, spacing: 12) {
                selectors
                HStack { displayControls; Spacer(minLength: 0) }
            }
        }
        .padding(16)
    }

    private var selectors: some View {
        HStack(spacing: 16) {
            Menu {
                ForEach(viewModel.workflows) { workflow in
                    Button {
                        viewModel.selectWorkflow(workflow.id)
                        Task { await viewModel.loadSelectedRun(projectId: projectId) }
                    } label: {
                        if workflow.id == viewModel.selectedWorkflowID {
                            Label(workflow.name, systemImage: "checkmark")
                        } else { Text(workflow.name) }
                    }
                }
            } label: {
                Label(viewModel.selectedWorkflow?.name ?? "Workflows", systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
            }
            .disabled(viewModel.workflows.isEmpty)
            .accessibilityIdentifier("workflow-selector")

            Menu {
                Button("Definition only") { viewModel.selectRun(nil) }
                ForEach(viewModel.workflowRuns) { run in
                    Button {
                        viewModel.selectRun(run.id)
                        Task { await viewModel.loadSelectedRun(projectId: projectId) }
                    } label: {
                        Text("\(run.taskId ?? "Manual run") · \(ProjectWorkflowFormatting.title(run.status)) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(run.id)")
                    }
                }
            } label: {
                Label(viewModel.selectedRun.map { $0.taskId ?? "Manual run" } ?? "Definition only", systemImage: "clock.arrow.circlepath")
                    .lineLimit(1)
            }
            .disabled(viewModel.selectedWorkflow == nil)
            .accessibilityLabel("Workflow run")
            .accessibilityIdentifier("workflow-run-selector")
        }
        .buttonStyle(.borderless)
    }

    private var displayControls: some View {
        HStack(spacing: 12) {
            Picker("Display", selection: $showsGraph) {
                Text("Graph").tag(true)
                Text("Steps").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            Button {
                Task { await refresh() }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .labelStyle(.iconOnly)
                .disabled(viewModel.isLoading || viewModel.isLoadingDetail)
                .accessibilityIdentifier("workflow-refresh")
        }
    }

    @ViewBuilder
    private func workflowContent(_ workflow: ProjectWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("v\(workflow.version) · \(workflow.nodes.count) steps · \(workflow.enabled ? "Enabled" : "Disabled")")
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer(minLength: 0)
                    if let run = viewModel.detail?.run ?? viewModel.selectedRun {
                        WorkflowStatusLabel(status: run.status)
                    }
                    if viewModel.isLoadingDetail { ProgressView().controlSize(.small) }
                }
                if let run = viewModel.detail?.run ?? viewModel.selectedRun {
                    Text("\(run.taskId ?? "Manual run") · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(theme.colors.textSecondary)
                    if run.workflowVersion != workflow.version {
                        Label("This run used v\(run.workflowVersion). The graph shows the current definition; inspect Steps for the recorded execution.", systemImage: "info.circle")
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
            .font(.caption)
            .padding(16)

            if showsGraph {
                if workflow.nodes.isEmpty {
                    ContentUnavailableView("No steps", systemImage: "arrow.triangle.branch")
                } else {
                    ProjectWorkflowGraph(workflow: workflow, detail: viewModel.canOverlayRun ? viewModel.detail : nil) {
                        inspection = WorkflowInspection(nodeID: $0.id)
                    }
                }
            } else {
                stepsContent(workflow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stepsContent(_ workflow: ProjectWorkflow) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let detail = viewModel.detail {
                    ForEach(detail.pendingActions.filter { $0.resolvedAt == nil }) { action in
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Waiting for \(action.assignee)", systemImage: "person.crop.circle.badge.clock")
                                .font(.headline)
                            Text(action.prompt).textSelection(.enabled)
                        }
                        .padding(16)
                        Divider()
                    }
                    if detail.steps.isEmpty {
                        Text("No steps have executed yet.").foregroundStyle(.secondary).padding(16)
                    }
                    ForEach(detail.steps.sorted { $0.startedAt < $1.startedAt }) { step in
                        Button {
                            inspection = WorkflowInspection(nodeID: step.nodeId, stepID: step.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.canOverlayRun ? (workflow.nodes.first { $0.id == step.nodeId }?.title ?? step.nodeId) : step.nodeId)
                                    .font(.headline).foregroundStyle(theme.colors.textPrimary)
                                WorkflowStatusLabel(status: step.status)
                                Text(step.startedAt, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                                if let error = step.error { Text(error).foregroundStyle(.red).lineLimit(3) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workflow-step-\(step.id)")
                        Divider()
                    }
                } else if viewModel.selectedRunID == nil {
                    ForEach(workflow.nodes) { node in
                        Button { inspection = WorkflowInspection(nodeID: node.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(node.title).font(.headline).foregroundStyle(theme.colors.textPrimary)
                                Text(ProjectWorkflowFormatting.title(node.type)).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier("project-workflow-steps")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
            Spacer(minLength: 0)
            Button("Try Again") { Task { await refresh() } }
        }
        .font(.callout).padding(16)
    }

    private func inspectionSteps(_ item: WorkflowInspection) -> [ProjectWorkflowRunStep] {
        guard let detail = viewModel.detail else { return [] }
        if let id = item.stepID { return detail.steps.filter { $0.id == id } }
        guard viewModel.canOverlayRun else { return [] }
        return detail.steps.filter { $0.nodeId == item.nodeID }.sorted { $0.startedAt < $1.startedAt }
    }

    private func refresh() async {
        await viewModel.load(projectId: projectId)
        guard !Task.isCancelled else { return }
        await viewModel.loadSelectedRun(projectId: projectId)
    }

    private func poll() async {
        await refresh()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            if scenePhase == .active { await refresh() }
        }
    }
}

private struct WorkflowInspection: Identifiable {
    let nodeID: String
    var stepID: String? = nil
    var id: String { stepID ?? nodeID }
}
