import SwiftUI

@MainActor
struct BrowserTaskEditor: View {
    let store: BrowserOrganizerStore
    @State var task: BrowserPersonalTask
    var currentPage: URL?
    var onSaved: () -> Void = {}
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    private var isExisting: Bool { store.tasks.contains { $0.id == task.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $task.title, axis: .vertical)
                        .accessibilityLabel("Task title")
                        .accessibilityIdentifier("browser-task-title")
                    TextField("Details", text: $task.details, axis: .vertical).lineLimit(3...8)
                        .accessibilityLabel("Task details")
                }
                Section("Schedule") {
                    Toggle("Due date", isOn: Binding(get: { task.dueAt != nil }, set: { task.dueAt = $0 ? .now : nil }))
                        .accessibilityIdentifier("browser-task-has-date")
                    if task.dueAt != nil {
                        DatePicker("Due", selection: Binding(get: { task.dueAt ?? .now }, set: { task.dueAt = $0 }))
                    }
                    Picker("Priority", selection: $task.priority) {
                        ForEach(BrowserPersonalTask.Priority.allCases) { Text($0.title).tag($0) }
                    }
                }
                if task.pageURL != nil || currentPage != nil {
                    Section("Page") {
                        if let url = task.pageURL {
                            Text(url.absoluteString).font(.caption).textSelection(.enabled)
                            Button("Remove page link") { task.pageURL = nil }
                        }
                        if let currentPage {
                            Button("Attach current page") { task.pageURL = currentPage }
                        }
                    }
                }
                if isExisting {
                    Section {
                        Toggle("Completed", isOn: Binding(get: { task.isCompleted }, set: { task.completedAt = $0 ? .now : nil }))
                        Button("Delete task", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isExisting ? "Edit task" : "New task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.saveTask(task) { onSaved(); dismiss() } }
                        .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("browser-task-save")
                }
            }
            .confirmationDialog("Delete this task?", isPresented: $confirmsDelete) {
                Button("Delete task", role: .destructive) { store.deleteTask(task.id); dismiss() }
            }
        }
#if os(macOS)
        .frame(width: 480, height: 560)
#else
        .presentationDetents([.large])
        .tint(.blue)
#endif
    }
}
