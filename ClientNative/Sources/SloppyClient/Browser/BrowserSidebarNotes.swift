import SwiftUI

/// A single-column notebook that leaves the browser's detail pane in place.
@MainActor
struct BrowserSidebarNotes: View {
    let state: BrowserWorkspaceState
    private var query: String {
        get { state.sidebarDrafts.noteQuery }
        nonmutating set { state.sidebarDrafts.noteQuery = newValue }
    }
    private var selection: UUID? {
        get { state.sidebarDrafts.noteSelection }
        nonmutating set { state.sidebarDrafts.noteSelection = newValue }
    }

    var body: some View {
        Group {
            if let selection, state.organizer.note(selection) != nil {
                BrowserNoteEditor(state: state, noteID: selection,
                    onDeleted: { self.selection = nil }, onBack: { self.selection = nil },
                    onOpenPage: { state.open($0, inNewTab: true) })
                    .id(selection)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Text("Notes").font(.headline)
                        Spacer()
                        Button("New note", systemImage: "square.and.pencil") {
                            query = ""
                            state.sidebarDrafts.notePreview = false
                            selection = state.organizer.createNote()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("New note")
                        .accessibilityIdentifier("browser-note-new")
                    }.padding([.horizontal, .top], 12)
                    TextField("Search notes", text: Binding(get: { query }, set: { query = $0 }))
                        .textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                    List {
                        ForEach(state.organizer.filteredNotes(query: query)) { note in
                            Button { selection = note.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(note.displayTitle).fontWeight(.medium).lineLimit(1)
                                        if note.isPinned { Image(systemName: "pin.fill").font(.caption) }
                                    }
                                    Text(note.body.isEmpty ? "Empty note" : note.body)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("browser-note-\(note.id)")
                        }
                    }
                    .overlay {
                        if state.organizer.filteredNotes(query: query).isEmpty {
                            Text(query.isEmpty ? "Create your first note using the button above." : "No matching notes.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("browser-notes-screen")
    }
}
