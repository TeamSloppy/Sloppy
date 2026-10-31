import SwiftUI

@MainActor
struct BrowserTasksView: View {
    let state: BrowserWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.browserSidebarLayout) private var isSidebar
    @State private var localDrafts = BrowserSidebarDrafts()
    @State private var taskDraft: BrowserPersonalTask?
    @State private var now = Date()

    private var drafts: BrowserSidebarDrafts { isSidebar ? state.sidebarDrafts : localDrafts }
    private var query: String {
        get { drafts.taskQuery }
        nonmutating set { drafts.taskQuery = newValue }
    }
    private var quickTitle: String {
        get { drafts.taskTitle }
        nonmutating set { drafts.taskTitle = newValue }
    }
    private var filter: BrowserTaskFilter {
        get { drafts.taskFilter }
        nonmutating set { drafts.taskFilter = newValue }
    }

    private var tasks: [BrowserPersonalTask] {
        state.organizer.filteredTasks(query: query, filter: filter, now: now)
    }

    var body: some View {
        Group {
            if isSidebar { taskContent }
            else {
                NavigationStack {
                    taskContent
                        .navigationTitle("Tasks")
                        .searchable(text: Binding(get: { query }, set: { query = $0 }), prompt: "Search tasks")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                }
            }
        }
        .sheet(item: $taskDraft) { draft in
            let createsTask = !state.organizer.tasks.contains { $0.id == draft.id }
            BrowserTaskEditor(store: state.organizer, task: draft, currentPage: state.selectedTab?.url, onSaved: {
                guard createsTask else { return }
                quickTitle = ""
                filter = .all
                query = ""
            })
        }
#if os(macOS)
        .frame(minWidth: isSidebar ? nil : 580, idealWidth: isSidebar ? nil : 680,
               minHeight: isSidebar ? nil : 520, idealHeight: isSidebar ? nil : 700)
#else
        .presentationDetents([.large])
        .tint(.blue)
#endif
        .task {
            while !Task.isCancelled {
                now = .now
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .accessibilityIdentifier("browser-tasks-screen")
    }

    private var taskContent: some View {
        VStack(spacing: 0) {
            if isSidebar {
                HStack {
                    Text("Tasks").font(.headline)
                    Spacer()
                    detailsButton.labelStyle(.iconOnly)
                }.padding([.horizontal, .top], 12)
                TextField("Search tasks", text: Binding(get: { query }, set: { query = $0 })).textFieldStyle(.roundedBorder).padding([.horizontal, .top], 12)
            }
            HStack {
                TextField("Add a task…", text: Binding(get: { quickTitle }, set: { quickTitle = $0 }))
                    .textFieldStyle(.roundedBorder).onSubmit(addQuickTask)
                    .accessibilityIdentifier("browser-task-quick-title")
                    .accessibilityLabel("New task title")
                Button("Add", systemImage: "plus", action: addQuickTask)
                    .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("browser-task-quick-add")
                if !isSidebar { detailsButton }
            }
            .padding(isSidebar ? 12 : 16)
            taskFilter
                .padding(.horizontal, isSidebar ? 12 : 16).padding(.bottom, 12)
            List {
                ForEach(BrowserTaskGroup.allCases, id: \.self) { group in
                    let grouped = tasks.filter { state.organizer.taskGroup($0, now: now) == group }
                    if !grouped.isEmpty {
                        Section(group.rawValue) { ForEach(grouped) { taskRow($0) } }
                    }
                }
            }
            .overlay {
                if tasks.isEmpty {
                    if isSidebar {
                        Text(query.isEmpty ? "Add a task or choose another filter." : "No matching tasks.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
                    } else {
                        ContentUnavailableView(query.isEmpty ? "No tasks here yet" : "No matching tasks", systemImage: "checklist",
                            description: Text(query.isEmpty ? "Add a task or choose another filter." : "Try another search."))
                    }
                }
            }
            Text("Personal tasks · saved on this device").font(.caption).foregroundStyle(.secondary).padding(12)
        }
    }

    private var detailsButton: some View {
        Button("Details", systemImage: "slider.horizontal.3") {
            taskDraft = BrowserPersonalTask(title: quickTitle)
        }
        .accessibilityIdentifier("browser-task-new-details")
    }

    private var taskFilter: some View {
        Group {
            if isSidebar { filterPicker.pickerStyle(.menu) }
            else { filterPicker.pickerStyle(.segmented) }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterPicker: some View {
        Picker("Show tasks", selection: Binding(get: { filter }, set: { filter = $0 })) {
            ForEach(BrowserTaskFilter.allCases) { Text($0.rawValue).tag($0) }
        }
    }

    private func taskRow(_ task: BrowserPersonalTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { state.organizer.toggleTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3).frame(minWidth: 32, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(task.isCompleted ? "Reopen" : "Complete"): \(task.title)")
            .accessibilityIdentifier("browser-task-toggle-\(task.id)")
            Button { taskDraft = task } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(task.title).strikethrough(task.isCompleted).frame(maxWidth: .infinity, alignment: .leading)
                        if task.priority == .high { Image(systemName: "exclamationmark").accessibilityLabel("High priority") }
                    }
                    if let date = task.dueAt {
                        Label { Text(date, format: .dateTime.month().day().hour().minute()) } icon: { Image(systemName: "calendar") }
                            .font(.caption).foregroundStyle(task.dueAt.map { $0 < now && !task.isCompleted } == true ? .red : .secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browser-task-edit-\(task.id)")
            if let url = task.pageURL {
                Button {
                    state.open(url, inNewTab: true)
                    if !isSidebar { dismiss() }
                } label: { Image(systemName: "link").frame(minWidth: 32, minHeight: 36) }
                    .buttonStyle(.borderless).accessibilityLabel("Open linked page for \(task.title)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-task-row-\(task.id)")
    }

    private func addQuickTask() {
        guard state.organizer.saveTask(.init(title: quickTitle)) else { return }
        quickTitle = ""
        filter = .all
        query = ""
    }
}
