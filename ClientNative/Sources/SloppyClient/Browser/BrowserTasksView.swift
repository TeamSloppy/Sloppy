import SwiftUI

@MainActor
struct BrowserTasksView: View {
    let state: BrowserWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.browserSidebarLayout) private var isSidebar
    @State private var localDrafts = BrowserSidebarDrafts()
    @State private var taskDraft: BrowserPersonalTask?
    @State private var now = Date()
    @FocusState private var isNewTaskFocused: Bool

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
#if os(macOS)
        .background {
            if isSidebar, drafts.newTask != nil {
                Button("Cancel new task", role: .cancel, action: cancelNewTask)
                    .keyboardShortcut(.cancelAction)
                    .opacity(Double.zero)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
#endif
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-tasks-screen")
    }

    private var taskContent: some View {
        VStack(spacing: 0) {
            if isSidebar {
                HStack {
                    Text("Tasks").font(.headline)
                    Spacer()
                    detailsButton.labelStyle(.iconOnly).buttonStyle(.plain)
                        .frame(width: 28, height: 28)
                }.padding([.horizontal, .top], 12)
                sidebarSearchAndFilter
                HStack {
                    Button("New task", systemImage: "plus", action: beginNewTask)
                        .buttonStyle(.plain).font(.callout)
                        .frame(minHeight: 28)
                        .accessibilityIdentifier("browser-task-new")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            } else {
                quickAddControls
                taskFilter.padding(.horizontal, 16).padding(.bottom, 12)
            }
            if isSidebar { taskList.listStyle(.plain) }
            else { taskList }
            if !isSidebar {
                Text("Personal tasks · saved on this device").font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    private var sidebarSearchAndFilter: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tasks", text: Binding(get: { query }, set: { query = $0 }))
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search tasks")
                    .accessibilityIdentifier("browser-task-search")
            }
            .font(.callout).padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            Menu {
                ForEach(BrowserTaskFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        if filter == option { Label(option.rawValue, systemImage: "checkmark") }
                        else { Text(option.rawValue) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filter.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                }.font(.caption)
            }
#if os(macOS)
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
#endif
            .buttonStyle(.plain).fixedSize()
            .accessibilityLabel("Show tasks")
            .accessibilityValue(filter.rawValue)
            .accessibilityIdentifier("browser-task-filter")
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var quickAddControls: some View {
        HStack {
            TextField("Add a task…", text: Binding(get: { quickTitle }, set: { quickTitle = $0 }))
                .textFieldStyle(.roundedBorder).onSubmit(addQuickTask)
                .accessibilityIdentifier("browser-task-quick-title")
                .accessibilityLabel("New task title")
            Button("Add", systemImage: "plus", action: addQuickTask)
                .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("browser-task-quick-add")
            detailsButton
        }
        .padding(16)
    }

    private var taskList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(BrowserTaskGroup.allCases, id: \.self) { group in
                    let grouped = tasks.filter { state.organizer.taskGroup($0, now: now) == group }
                    let hasNewTask = isSidebar && group == .anytime && drafts.newTask != nil
                    if !grouped.isEmpty || hasNewTask {
                        Section(group.rawValue) {
                            ForEach(grouped) { taskRow($0) }
                            if hasNewTask, let task = drafts.newTask {
                                newTaskRow.id(task.id)
                            }
                        }
                    }
                }
            }
            .onChange(of: drafts.newTask?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .overlay {
                if tasks.isEmpty && drafts.newTask == nil {
                    if isSidebar {
                        Text(query.isEmpty ? "Add a task or choose another filter." : "No matching tasks.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
                    } else {
                        ContentUnavailableView(query.isEmpty ? "No tasks here yet" : "No matching tasks", systemImage: "checklist",
                            description: Text(query.isEmpty ? "Add a task or choose another filter." : "Try another search."))
                    }
                }
            }
        }
    }

    private var newTaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                .frame(width: 24, height: 28)
            TextField("Task title", text: Binding(
                get: { drafts.newTask?.title ?? "" },
                set: { drafts.newTask?.title = $0 }
            ))
            .textFieldStyle(.plain)
            .focused($isNewTaskFocused)
            .onSubmit(commitNewTask)
            .accessibilityLabel("New task title")
            .accessibilityIdentifier("browser-task-inline-title")
            .onAppear { isNewTaskFocused = true }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .accessibilityIdentifier("browser-task-new-row")
    }

    private func beginNewTask() {
        query = ""
        filter = .all
        if drafts.newTask == nil { drafts.newTask = BrowserPersonalTask(title: "") }
        isNewTaskFocused = true
    }

    private func commitNewTask() {
        guard let task = drafts.newTask else { return }
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelNewTask()
            return
        }
        guard state.organizer.saveTask(task) else { return }
        cancelNewTask()
    }

    private func cancelNewTask() {
        drafts.newTask = nil
        isNewTaskFocused = false
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
        HStack(alignment: .center, spacing: 10) {
            Button { state.organizer.toggleTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3).frame(minWidth: isSidebar ? 24 : 32, minHeight: isSidebar ? 28 : 36)
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
        .padding(.vertical, isSidebar ? 2 : 6)
        .listRowInsets(isSidebar ? EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12) : nil)
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
