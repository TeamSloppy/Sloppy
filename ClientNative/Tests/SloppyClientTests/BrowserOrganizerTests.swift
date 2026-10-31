import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser notes and personal tasks")
@MainActor
struct BrowserOrganizerTests {
    private func fixture(_ run: (BrowserOrganizerStore, UserDefaults) throws -> Void) throws {
        let name = "BrowserOrganizer.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try run(BrowserOrganizerStore(defaults: defaults), defaults)
    }

    @Test func notesAutosavePreserveMarkdownAndRestorePinAndPage() throws {
        try fixture { store, defaults in
            let url = try #require(URL(string: "https://user:secret@example.com/release?q=1#section"))
            let first = store.createNote(pageURL: url, now: Date(timeIntervalSince1970: 10))
            let second = store.createNote(now: Date(timeIntervalSince1970: 20))
            let body = "## Before release\n\n- [ ] Ship 🚀\n\n```swift\nlet version = 1\n```\n"
            store.updateNote(first, now: Date(timeIntervalSince1970: 30)) {
                $0.title = "Release"; $0.body = body; $0.isPinned = true
            }
            store.updateNote(second, now: Date(timeIntervalSince1970: 40)) { $0.title = "More recent" }
            let restored = BrowserOrganizerStore(defaults: defaults)
            #expect(restored.filteredNotes(query: "").map(\.id) == [first, second])
            #expect(restored.note(first)?.body == body)
            #expect(restored.note(first)?.pageURL?.user == nil)
            #expect(restored.note(first)?.pageURL?.password == nil)
            #expect(restored.note(first)?.pageURL?.fragment == "section")
            #expect(restored.filteredNotes(query: "RELEASE").map(\.id) == [first])
            #expect(restored.filteredNotes(query: "example.com").map(\.id) == [first])
            #expect(restored.note(first)?.markdown == "# Release\n\n" + body)
        }
    }

    @Test func tasksValidateEditAndPersistWithoutDuplicating() throws {
        try fixture { store, defaults in
            #expect(!store.saveTask(.init(title: " \n ")))
            var task = BrowserPersonalTask(title: "  Review launch  ", details: "Checklist", dueAt: .distantFuture, priority: .high,
                pageURL: URL(string: "https://user:secret@example.com/task"))
            #expect(store.saveTask(task))
            task.title = "Review release"
            #expect(store.saveTask(task))
            let restored = BrowserOrganizerStore(defaults: defaults)
            #expect(restored.tasks.count == 1)
            #expect(restored.tasks.first?.id == task.id)
            #expect(restored.tasks.first?.title == "Review release")
            #expect(restored.tasks.first?.priority == .high)
            #expect(restored.tasks.first?.dueAt == .distantFuture)
            #expect(restored.tasks.first?.pageURL?.user == nil)
        }
    }

    @Test func filtersAndGroupsUseLocalCalendarBoundaries() throws {
        try fixture { store, _ in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 10800))
            let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
            let yesterday = BrowserPersonalTask(title: "Old", dueAt: now.addingTimeInterval(-86400))
            let today = BrowserPersonalTask(title: "Today", dueAt: now.addingTimeInterval(-3600))
            let tomorrow = BrowserPersonalTask(title: "Tomorrow", dueAt: now.addingTimeInterval(86400))
            let later = BrowserPersonalTask(title: "Later", dueAt: now.addingTimeInterval(86400 * 7))
            let anytime = BrowserPersonalTask(title: "Inbox")
            let completed = BrowserPersonalTask(title: "Done", dueAt: now, completedAt: now)
            for task in [yesterday, today, tomorrow, later, anytime, completed] { #expect(store.saveTask(task)) }
            #expect(store.taskGroup(yesterday, now: now, calendar: calendar) == .overdue)
            #expect(store.taskGroup(today, now: now, calendar: calendar) == .today)
            #expect(store.taskGroup(tomorrow, now: now, calendar: calendar) == .tomorrow)
            #expect(store.taskGroup(later, now: now, calendar: calendar) == .upcoming)
            #expect(store.taskGroup(anytime, now: now, calendar: calendar) == .anytime)
            #expect(store.filteredTasks(query: "", filter: .all, now: now, calendar: calendar).count == 5)
            #expect(store.filteredTasks(query: "", filter: .today, now: now, calendar: calendar).map(\.id) == [yesterday.id, today.id])
            #expect(store.filteredTasks(query: "", filter: .upcoming, now: now, calendar: calendar).map(\.id) == [tomorrow.id, later.id])
            #expect(store.filteredTasks(query: "DONE", filter: .completed, now: now, calendar: calendar).map(\.id) == [completed.id])
        }
    }

    @Test func completionCanBeReopenedAndSurvivesRestart() throws {
        try fixture { store, defaults in
            let task = BrowserPersonalTask(title: "Call", pageURL: URL(string: "https://example.com"))
            #expect(store.saveTask(task))
            let date = Date(timeIntervalSince1970: 100)
            store.toggleTask(task.id, now: date)
            let restored = BrowserOrganizerStore(defaults: defaults)
            #expect(restored.tasks.first?.completedAt == date)
            #expect(restored.filteredTasks(query: "", filter: .all, now: date).isEmpty)
            restored.toggleTask(task.id)
            #expect(restored.tasks.first?.isCompleted == false)
            #expect(restored.filteredTasks(query: "example.com", filter: .all, now: date).count == 1)
        }
    }

    @Test func taskOrderingUsesDateThenPriority() throws {
        try fixture { store, _ in
            let date = Date(timeIntervalSince1970: 100)
            let normal = BrowserPersonalTask(title: "Normal", dueAt: date)
            let high = BrowserPersonalTask(title: "High", dueAt: date, priority: .high)
            let low = BrowserPersonalTask(title: "Low", dueAt: date, priority: .low)
            for task in [normal, low, high] { #expect(store.saveTask(task)) }
            #expect(store.filteredTasks(query: "", filter: .all, now: date).map(\.id) == [high.id, normal.id, low.id])
        }
    }

    @Test func markdownCheckboxesIgnoreCodeAndPreserveUnicodeAndLineEndings() throws {
        let source = "# リリース\r\n- [ ] Ship 🚀\r\n````md\r\n- [ ] literal\r\n```\r\n- [x] still literal\r\n````\r\n1. [X] 完了\r\n"
        let items = BrowserNoteChecklist.items(in: source)
        #expect(items.map(\.line) == [1, 7])
        #expect(items.map(\.isComplete) == [false, true])
        let toggled = BrowserNoteChecklist.toggling(line: 1, in: source)
        #expect(toggled == source.replacingOccurrences(of: "- [ ] Ship 🚀", with: "- [x] Ship 🚀"))
        #expect(BrowserNoteChecklist.toggling(line: 3, in: source) == source)
        #expect(BrowserNoteChecklist.toggling(line: 1, in: toggled) == source)
        let parts = BrowserNotePreviewPart.parts(in: source)
        #expect(Set(parts.map(\.id)).count == parts.count)
        #expect(parts.compactMap(\.checkbox).count == 2)
        #expect(parts.compactMap(\.markdown).contains { $0.contains("literal") })
    }

    @Test func deletingOneItemKeepsOtherNotesTasksAndExistingBrowserData() throws {
        try fixture { store, defaults in
            defaults.set("keep", forKey: "other.browser.state")
            let first = store.createNote()
            let second = store.createNote()
            let task = BrowserPersonalTask(title: "Keep task")
            #expect(store.saveTask(task))
            store.deleteNote(first)
            #expect(store.note(first) == nil)
            #expect(store.note(second) != nil)
            #expect(store.tasks.count == 1)
            store.deleteTask(task.id)
            #expect(store.tasks.isEmpty)
            #expect(defaults.string(forKey: "other.browser.state") == "keep")
        }
    }
}
