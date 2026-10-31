import Foundation
import Observation

struct BrowserNote: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var body = ""
    var pageURL: URL?
    var isPinned = false
    var updatedAt = Date()
    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled note" : title }
    var markdown: String { "# \(displayTitle)\n\n\(body)" }
}

struct BrowserPersonalTask: Codable, Equatable, Identifiable {
    enum Priority: Int, Codable, CaseIterable, Identifiable {
        case normal, low, high
        var id: Int { rawValue }
        var title: String {
            switch self { case .normal: "Normal"; case .low: "Low"; case .high: "High" }
        }
    }
    var id = UUID()
    var title: String
    var details = ""
    var dueAt: Date?
    var priority = Priority.normal
    var pageURL: URL?
    var completedAt: Date?
    var createdAt = Date()
    var isCompleted: Bool { completedAt != nil }
}

enum BrowserTaskFilter: String, CaseIterable, Identifiable {
    case all = "All tasks", today = "Today", upcoming = "Upcoming", completed = "Completed"
    var id: String { rawValue }
}

enum BrowserTaskGroup: String, CaseIterable {
    case overdue = "Overdue", today = "Today", tomorrow = "Tomorrow", upcoming = "Upcoming", anytime = "Anytime", completed = "Completed"
}

/// Personal browser content is device-local and separate from project/server tasks.
@Observable @MainActor
final class BrowserOrganizerStore {
    static let shared = BrowserOrganizerStore()
    private static let key = "sloppy.browser.organizer.v1"
    private struct Snapshot: Codable {
        var notes: [BrowserNote] = []
        var tasks: [BrowserPersonalTask] = []
    }
    private let defaults: UserDefaults
    private var snapshot: Snapshot
    var notes: [BrowserNote] { snapshot.notes }
    var tasks: [BrowserPersonalTask] { snapshot.tasks }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    @discardableResult
    func createNote(pageURL: URL? = nil, now: Date = .now) -> UUID {
        let note = BrowserNote(pageURL: BrowserSearchEngine.websiteURL(pageURL), updatedAt: now)
        snapshot.notes.insert(note, at: 0)
        persist()
        return note.id
    }

    func note(_ id: UUID) -> BrowserNote? { notes.first { $0.id == id } }

    func updateNote(_ id: UUID, now: Date = .now, change: (inout BrowserNote) -> Void) {
        guard let index = snapshot.notes.firstIndex(where: { $0.id == id }) else { return }
        change(&snapshot.notes[index])
        snapshot.notes[index].pageURL = BrowserSearchEngine.websiteURL(snapshot.notes[index].pageURL)
        snapshot.notes[index].updatedAt = now
        persist()
    }

    func deleteNote(_ id: UUID) {
        snapshot.notes.removeAll { $0.id == id }
        persist()
    }

    func filteredNotes(query: String) -> [BrowserNote] {
        notes.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
                || ($0.pageURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
    }

    @discardableResult
    func saveTask(_ task: BrowserPersonalTask) -> Bool {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return false }
        task.pageURL = BrowserSearchEngine.websiteURL(task.pageURL)
        if let index = snapshot.tasks.firstIndex(where: { $0.id == task.id }) { snapshot.tasks[index] = task }
        else { snapshot.tasks.append(task) }
        persist()
        return true
    }

    func toggleTask(_ id: UUID, now: Date = .now) {
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tasks[index].completedAt = snapshot.tasks[index].isCompleted ? nil : now
        persist()
    }

    func deleteTask(_ id: UUID) { snapshot.tasks.removeAll { $0.id == id }; persist() }

    func taskGroup(_ task: BrowserPersonalTask, now: Date, calendar: Calendar = .current) -> BrowserTaskGroup {
        if task.isCompleted { return .completed }
        guard let due = task.dueAt else { return .anytime }
        let today = calendar.startOfDay(for: now)
        if due < today { return .overdue }
        if calendar.isDate(due, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(due, inSameDayAs: tomorrow) { return .tomorrow }
        return .upcoming
    }

    func filteredTasks(query: String, filter: BrowserTaskFilter, now: Date, calendar: Calendar = .current) -> [BrowserPersonalTask] {
        tasks.filter { task in
            let group = taskGroup(task, now: now, calendar: calendar)
            let included: Bool = switch filter {
            case .all: !task.isCompleted
            case .today: group == .today || group == .overdue
            case .upcoming: group == .tomorrow || group == .upcoming
            case .completed: task.isCompleted
            }
            return included && (query.isEmpty || task.title.localizedCaseInsensitiveContains(query)
                || task.details.localizedCaseInsensitiveContains(query)
                || (task.pageURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false))
        }.sorted {
            if $0.isCompleted && $1.isCompleted { return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            func rank(_ priority: BrowserPersonalTask.Priority) -> Int {
                switch priority { case .high: 0; case .normal: 1; case .low: 2 }
            }
            if $0.priority != $1.priority { return rank($0.priority) < rank($1.priority) }
            return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    func toggleChecklist(noteID: UUID, line: Int) {
        updateNote(noteID) { note in note.body = BrowserNoteChecklist.toggling(line: line, in: note.body) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }
}
