import SwiftUI
import SloppyClientUI

/// A single-column notebook that leaves the browser's detail pane in place.
@MainActor
struct BrowserSidebarNotes: View {
    let state: BrowserWorkspaceState
    @Environment(\.theme) private var theme
    @FocusState private var isSearchFocused: Bool
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
                    searchField
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        notesList(now: context.date)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-notes-screen")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.colors.textSecondary)
            TextField("Search notes", text: Binding(get: { query }, set: { query = $0 }),
                prompt: Text("Search notes").foregroundStyle(theme.colors.textSecondary))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel("Search notes")
                .accessibilityIdentifier("browser-note-search")
        }
        .font(.callout)
        .foregroundStyle(theme.colors.textPrimary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular.tint(theme.colors.textPrimary.opacity(0.06)).interactive(), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isSearchFocused ? theme.colors.textPrimary.opacity(0.8) : theme.colors.textSecondary.opacity(0.5),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
    }

    private func notesList(now: Date) -> some View {
        let notes = state.organizer.filteredNotes(query: query)
        return List {
            ForEach(BrowserNoteDaySection.sections(from: notes)) { section in
                Section(section.title(relativeTo: now)) {
                    ForEach(section.notes) { noteRow($0) }
                }
            }
        }
        .overlay {
            if notes.isEmpty {
                Text(query.isEmpty ? "Create your first note using the button above." : "No matching notes.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
            }
        }
    }

    private func noteRow(_ note: BrowserNote) -> some View {
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
