import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct WorkspaceCreationForm: View {
    let viewModel: MainViewModel
    @Environment(\.theme) private var theme
    private var model: WorkspaceSurfaceModel { viewModel.surface }
    var body: some View {
        ZStack {
            Color.black.opacity(0.5 as Float)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    Spacer()
                    WorkspaceIconButton(icon: .close) { model.creation = nil }
                }
                if model.creation == .scheduled {
                    Text("Agent").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                    ScrollView(.horizontal, respectsSafeArea: false) {
                        HStack(spacing: 8) {
                            ForEach(model.agents) { agent in
                                WorkspaceAction(title: agent.displayName, primary: model.creationAgentID == agent.id) { model.creationAgentID = agent.id }
                            }
                        }
                    }.frame(height: 34)
                    field("Delivery channel", value: Binding(get: { model.creationChannelID }, set: { model.creationChannelID = $0 }))
                    field("Cron schedule", value: Binding(get: { model.creationSchedule }, set: { model.creationSchedule = $0 }))
                    Text("Prompt").font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                    TextEditor("What should the agent do?", text: Binding(get: { model.creationCommand }, set: { model.creationCommand = $0 }), showsLineNumbers: false, wrapsLines: true)
                        .font(.system(size: 14)).frame(height: 110).background(theme.colors.background)
                } else {
                    field("Name", value: Binding(get: { model.creationName }, set: { model.creationName = $0 }))
                    if model.creation == .automation {
                        field("Workflow ID", value: Binding(get: { model.creationWorkflowID }, set: { model.creationWorkflowID = $0 }))
                        field("Repository (owner/name)", value: Binding(get: { model.creationRepository }, set: { model.creationRepository = $0 }))
                        ScrollView(.horizontal, respectsSafeArea: false) {
                            HStack {
                                ForEach(ProjectAutomationTriggerKind.allCases, id: \.self) { trigger in
                                    WorkspaceAction(title: trigger.title, primary: model.creationTrigger == trigger) { model.creationTrigger = trigger }
                                }
                            }
                        }.frame(height: 34)
                        if model.creationTrigger == .cron {
                            field("Cron schedule", value: Binding(get: { model.creationSchedule }, set: { model.creationSchedule = $0 }))
                        }
                        if model.creationTrigger == .webhook {
                            field("Webhook secret ID", value: Binding(get: { model.creationCommand }, set: { model.creationCommand = $0 }))
                        }
                        Text("Task behavior").font(.system(size: 12))
                        ScrollView(.horizontal, respectsSafeArea: false) {
                            HStack {
                                ForEach(ProjectAutomationTaskMode.allCases, id: \.self) { mode in
                                    WorkspaceAction(title: mode.title, primary: model.creationTaskMode == mode) { model.creationTaskMode = mode }
                                }
                            }
                        }.frame(height: 34)
                        HStack {
                            ForEach(ProjectAutomationPermissionsScope.allCases, id: \.self) { scope in
                                WorkspaceAction(title: scope.title, primary: model.creationPermissions == scope) { model.creationPermissions = scope }
                            }
                        }
                    }
                }
                ForEach(model.errors, id: \.self) { error in Text(error).font(.system(size: 12)).foregroundColor(theme.colors.statusBlocked).lineLimit(3) }
                HStack {
                    Spacer()
                    WorkspaceAction(title: "Cancel") { model.creation = nil }
                    WorkspaceAction(title: model.isSaving ? "Saving…" : "Create", icon: .add, primary: true) {
                        Task { await model.saveCreation(project: viewModel.activeProject) }
                    }.disabled(model.isSaving).accessibilityIdentifier("workspace.creation.save")
                }
            }.padding(24).frame(maxWidth: 500)
                .background { RoundedRectangle(cornerRadius: 18).fill(theme.colors.surfaceRaised) }
        }.foregroundColor(theme.colors.textPrimary).accessibilityIdentifier("workspace.creation")
    }
    private var title: String {
        switch model.creation { case .scheduled: "New scheduled task"; case .canvas: "Create Workspace"; case .automation: "New Automation"; case nil: "Create" }
    }
    private func field(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
            TextField(label, text: value).textFieldStyle(PlainTextFieldStyle()).font(.system(size: 14))
                .padding(.horizontal, 12).frame(height: 38)
                .background { RoundedRectangle(cornerRadius: 8).fill(theme.colors.background) }
        }
    }
}
