import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProjectTaskProperties: View {
    let task: APIProjectTask
    let isSaving: Bool
    let onSave: (APIProjectTaskUpdateRequest) -> Void
    let onCancel: () -> Void
    @State private var title: String
    @State private var description: String
    @State private var status: String
    @State private var priority: String
    @State private var actor: String
    @State private var tags: String
    @Environment(\.theme) private var theme
    init(task: APIProjectTask, isSaving: Bool, onSave: @escaping (APIProjectTaskUpdateRequest) -> Void, onCancel: @escaping () -> Void) {
        self.task = task; self.isSaving = isSaving; self.onSave = onSave; self.onCancel = onCancel
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority ?? "medium")
        _actor = State(initialValue: task.actorId ?? "")
        _tags = State(initialValue: (task.tags ?? []).joined(separator: ", "))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Task properties").font(.system(size: 20, weight: .semibold))
            TextField("Title", text: $title)
                .padding(8).background(theme.colors.surface)
            Text("Description (Markdown)").font(.system(size: 12))
            TextEditor(text: $description, showsLineNumbers: false, wrapsLines: true).font(.system(size: 14)).frame(height: 160)
            choices("Status", values: ["backlog", "ready", "in_progress", "needs_review", "done", "cancelled"], selection: $status)
            choices("Priority", values: ["low", "medium", "high", "urgent"], selection: $priority)
            TextField("Agent ID", text: $actor)
                .padding(8).background(theme.colors.surface)
            TextField("Tags, separated by commas", text: $tags)
                .padding(8).background(theme.colors.surface)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button(isSaving ? "Saving…" : "Save properties") {
                    onSave(APIProjectTaskUpdateRequest(title: title.trimmingCharacters(in: .whitespacesAndNewlines), description: description,
                        priority: priority, status: status, actorId: actor.trimmingCharacters(in: .whitespacesAndNewlines),
                        tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
                }.disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(16).background(theme.colors.surfaceRaised)
    }
    private func choices(_ title: String, values: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12))
            ScrollView(.horizontal, respectsSafeArea: false) {
                HStack(spacing: 5) {
                    ForEach(values, id: \.self) { value in
                        Button { selection.wrappedValue = value } label: {
                            Text(value.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 12)).padding(8)
                                .background(selection.wrappedValue == value ? theme.colors.surfaceGlow : theme.colors.surface)
                        }
                    }
                }
            }.frame(height: 36)
        }
    }
}
