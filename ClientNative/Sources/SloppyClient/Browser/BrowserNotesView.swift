import SwiftUI
import SloppyClientUI

@MainActor
struct BrowserNotesView: View {
    let state: BrowserWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UUID?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selection) {
                ForEach(state.organizer.filteredNotes(query: query)) { note in
                    NavigationLink(value: note.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(note.displayTitle, systemImage: note.isPinned ? "pin.fill" : "note.text")
                                .lineLimit(1)
                            if !note.body.isEmpty {
                                Text(note.body).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(note.updatedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("browser-note-\(note.id)")
                    .contextMenu {
                        Button(note.isPinned ? "Unpin" : "Pin", systemImage: "pin") {
                            state.organizer.updateNote(note.id) { $0.isPinned.toggle() }
                        }
                    }
                }
            }
            .overlay {
                if state.organizer.notes.isEmpty {
                    ContentUnavailableView("Your notes, close at hand", systemImage: "note.text",
                        description: Text("Create a Markdown note or keep thoughts about the current page."))
                } else if state.organizer.filteredNotes(query: query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search notes")
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New note", systemImage: "square.and.pencil") { createNote() }
                        .accessibilityIdentifier("browser-note-new")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            if let selection, state.organizer.note(selection) != nil {
                BrowserNoteEditor(state: state, noteID: selection, onDeleted: {
                    self.selection = nil
                    compactColumn = .sidebar
                }, onOpenPage: { url in
                    state.open(url, inNewTab: true)
                    dismiss()
                })
                .id(selection)
            } else {
                ContentUnavailableView {
                    Label("Select a note", systemImage: "note.text")
                } actions: { Button("New note") { createNote() } }
            }
        }
        .onChange(of: selection) { _, value in if value != nil { compactColumn = .detail } }
#if os(macOS)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 540, idealHeight: 700)
#else
        .presentationDetents([.large])
        .tint(.blue)
#endif
        .accessibilityIdentifier("browser-notes-screen")
    }

    private func createNote() {
        query = ""
        selection = state.organizer.createNote()
        compactColumn = .detail
    }
}
