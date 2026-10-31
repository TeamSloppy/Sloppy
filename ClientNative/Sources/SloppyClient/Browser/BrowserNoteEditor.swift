import SwiftUI
import UniformTypeIdentifiers
import SloppyClientUI

struct BrowserMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, UTType(filenameExtension: "md") ?? .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor
struct BrowserNoteEditor: View {
    let state: BrowserWorkspaceState
    let noteID: UUID
    var onDeleted: () -> Void = {}
    var onBack: () -> Void = {}
    var onOpenPage: ((URL) -> Void)?
    @Environment(\.theme) private var theme
    @Environment(\.browserSidebarLayout) private var isSidebar
    @State private var localPreview = false
    @State private var confirmsDelete = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var taskDraft: BrowserPersonalTask?

    private var preview: Bool {
        get { isSidebar ? state.sidebarDrafts.notePreview : localPreview }
        nonmutating set {
            if isSidebar { state.sidebarDrafts.notePreview = newValue }
            else { localPreview = newValue }
        }
    }

    private func field(_ keyPath: WritableKeyPath<BrowserNote, String>) -> Binding<String> {
        Binding(get: { state.organizer.note(noteID)?[keyPath: keyPath] ?? "" }, set: { value in
            state.organizer.updateNote(noteID) { $0[keyPath: keyPath] = value }
        })
    }

    var body: some View {
        if let note = state.organizer.note(noteID) {
            VStack(alignment: .leading, spacing: 16) {
                if isSidebar {
                    HStack {
                        Button("Notes", systemImage: "chevron.left", action: onBack)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("browser-sidebar-notes-back")
                        Spacer()
                        actionsMenu(note)
                    }
                }
                TextField("Note title", text: field(\.title))
                    .font(isSidebar ? .headline : .title2.weight(.semibold)).textFieldStyle(.plain)
                    .accessibilityIdentifier("browser-note-title")
                    .accessibilityLabel("Note title")
                if let url = note.pageURL {
                    Button {
                        if let onOpenPage { onOpenPage(url) }
                        else { state.open(url, inNewTab: true) }
                    } label: { Label(url.host ?? url.absoluteString, systemImage: "link").lineLimit(1) }
                    .accessibilityLabel("Open linked page: \(url.host ?? url.absoluteString)")
                }
                Picker("Note mode", selection: Binding(get: { preview }, set: { preview = $0 })) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityIdentifier("browser-note-mode")
                if preview {
                    previewContent(note)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markdown").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: field(\.body))
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Note body")
                            .accessibilityIdentifier("browser-note-body")
                    }
                }
                Text("Saved on this device").font(.caption).foregroundStyle(.secondary)
            }
            .padding(isSidebar ? 12 : 24)
            .background(theme.colors.background)
            .navigationTitle(isSidebar ? "Browse" : "Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if !isSidebar {
                    ToolbarItem(placement: .primaryAction) { actionsMenu(note) }
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmsDelete) {
                Button("Delete note", role: .destructive) { state.organizer.deleteNote(noteID); onDeleted() }
            }
            .fileExporter(isPresented: $exporting, document: BrowserMarkdownDocument(text: note.markdown),
                          contentType: UTType(filenameExtension: "md") ?? .plainText,
                          defaultFilename: exportName(note.displayTitle)) { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Could not export note", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
            .sheet(item: $taskDraft) { BrowserTaskEditor(store: state.organizer, task: $0, currentPage: state.selectedTab?.url) }
        } else {
            ContentUnavailableView("Note unavailable", systemImage: "note.text")
        }
    }

    private func actionsMenu(_ note: BrowserNote) -> some View {
        Menu {
            Button(note.isPinned ? "Unpin note" : "Pin note", systemImage: "pin") {
                state.organizer.updateNote(noteID) { $0.isPinned.toggle() }
            }
            if let url = state.selectedTab?.url {
                Button("Attach current page", systemImage: "link") {
                    state.organizer.updateNote(noteID) { $0.pageURL = url }
                }
            }
            if note.pageURL != nil {
                Button("Remove page link", systemImage: "link.badge.plus") {
                    state.organizer.updateNote(noteID) { $0.pageURL = nil }
                }
            }
            Button("Create task from note", systemImage: "checklist") {
                taskDraft = BrowserPersonalTask(title: note.title, details: note.body, pageURL: note.pageURL)
            }
            Button("Export Markdown…", systemImage: "square.and.arrow.up") { exporting = true }
            Divider()
            Button("Delete note", systemImage: "trash", role: .destructive) { confirmsDelete = true }
        } label: { Label("Note actions", systemImage: "ellipsis.circle") }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("browser-note-actions")
    }

    private func previewContent(_ note: BrowserNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if note.body.isEmpty { Text("Your Markdown preview will appear here.").foregroundStyle(.secondary) }
                else {
                    BrowserNotePreview(markdown: note.body) { line in
                        state.organizer.toggleChecklist(noteID: noteID, line: line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exportName(_ title: String) -> String {
        let sanitized = title.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines)).joined(separator: "-")
        return String(sanitized.prefix(100)) + ".md"
    }
}
