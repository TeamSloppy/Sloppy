#if os(macOS)
import Foundation
import SloppyClientCore
import Testing
@testable import SloppyClient

@MainActor
struct BrowserAgentWorkspaceTests {
    private func command(_ operation: String, tabID: UUID? = nil, url: String? = nil) throws -> WorkspaceBrowserCommand.Input {
        var input = ["operation": operation]
        if let tabID { input["tabId"] = tabID.uuidString }
        if let url { input["url"] = url }
        return try JSONDecoder().decode(WorkspaceBrowserCommand.Input.self, from: JSONEncoder().encode(input))
    }

    @Test func groupsObservedTabsAndRejectsStaleMembersAtomically() throws {
        let key = "agent-groups-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let state = BrowserWorkspaceState(defaults: defaults, startsPageMaintenance: false)
        let first = state.createBlankTab(), second = state.createBlankTab()
        let session = WorkspaceBrowserSession(apiClient: SloppyAPIClient(baseURL: URL(string: "https://test.invalid")!),
            agentID: "agent", sessionID: "session", workspace: state) {}
        func input(_ operation: String, _ title: String, _ ids: [UUID]) throws -> WorkspaceBrowserCommand.Input {
            try JSONDecoder().decode(WorkspaceBrowserCommand.Input.self, from: JSONSerialization.data(withJSONObject:
                ["operation": operation, "title": title, "tabIds": ids.map(\.uuidString)]))
        }
        _ = try session.executeGroups(input("create", "Travel research", [first, second]))
        let group = try #require(state.groups.first)
        #expect(state.tabs.allSatisfy { $0.groupID == group.id })
        #expect(throws: (any Error).self) { try session.executeGroups(input("create", "Invalid", [first, UUID()])) }
        #expect(state.groups.count == 1)
        _ = try session.executeGroups(input("move", "", [first]))
        #expect(state.tabs.first?.groupID == nil)
        let restored = BrowserWorkspaceState(defaults: defaults, startsPageMaintenance: false)
        #expect(restored.tabs.last?.groupID == group.id)
        #expect(restored.groups.first?.title == "Travel research")
    }

    @Test func savesOrganizerEntriesAndRejectsInvalidDatesWithoutWriting() throws {
        let key = "agent-organizer-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let state = BrowserWorkspaceState(defaults: defaults, startsPageMaintenance: false)
        state.createBlankTab()
        let session = WorkspaceBrowserSession(apiClient: SloppyAPIClient(baseURL: URL(string: "https://test.invalid")!),
            agentID: "agent", sessionID: "session", workspace: state) {}
        func input(_ values: [String: String]) throws -> WorkspaceBrowserCommand.Input {
            try JSONDecoder().decode(WorkspaceBrowserCommand.Input.self, from: JSONEncoder().encode(values))
        }
        let note = try session.executeOrganizer("create_note", input: input(["title": "Sources", "text": "- [ ] Read", "url": "https://user:secret@example.com/article"]))
        #expect(note.createdEntry?.kind == "note")
        #expect(state.organizer.notes.first?.body == "- [ ] Read")
        #expect(state.organizer.notes.first?.pageURL?.user == nil)
        let todo = try session.executeOrganizer("create_todo", input: input(["title": "Read", "dueAt": "2026-11-03T09:00:00+03:00", "priority": "high"]))
        #expect(todo.createdEntry?.kind == "todo")
        #expect(state.organizer.tasks.first?.priority == .high)
        #expect(state.organizer.tasks.first?.dueAt != nil)
        #expect(throws: (any Error).self) { try session.executeOrganizer("create_todo", input: input(["title": "Bad", "dueAt": "tomorrow"])) }
        #expect(throws: (any Error).self) { try session.executeOrganizer("create_note", input: input(["title": " "])) }
        let restored = BrowserOrganizerStore(defaults: defaults)
        #expect(restored.notes.count == 1 && restored.tasks.count == 1)
        #expect(restored.tasks.first?.id.uuidString == todo.createdEntry?.id)
    }

    @Test func managesActualTabsAndKeepsStableIDs() throws {
        let key = "agent-workspace-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let state = BrowserWorkspaceState(defaults: defaults, startsPageMaintenance: false)
        let first = state.createBlankTab()
        let session = WorkspaceBrowserSession(apiClient: SloppyAPIClient(baseURL: URL(string: "https://test.invalid")!),
            agentID: "agent", sessionID: "session", viewModel: state.selectedPage, workspace: state) {}
        #expect(session.binding.capabilities?.contains("tabs_v1") == true)
        _ = try session.executeTabs(command("open"))
        let second = try #require(state.selectedID)
        #expect(first != second)
        let list = try session.executeTabs(command("list"))
        #expect(list.workspace?.tabs.map(\.id) == [first.uuidString, second.uuidString])
        _ = try session.executeTabs(command("select", tabID: first))
        #expect(state.selectedID == first)
        #expect(session.viewModel === state.selectedPage)
        _ = try session.executeTabs(command("close", tabID: second))
        #expect(state.tabs.map(\.id) == [first])
        #expect(throws: (any Error).self) { try session.executeTabs(command("select", tabID: second)) }
        #expect(throws: (any Error).self) { try session.executeTabs(command("open", url: "file:///tmp/secret")) }
        #expect(state.tabs.count == 1)
        _ = try session.executeTabs(command("close", tabID: first))
        #expect(state.tabs.isEmpty)
        _ = try session.executeTabs(command("open"))
        #expect(state.tabs.count == 1)
        #expect(BrowserWorkspaceState(defaults: defaults, startsPageMaintenance: false).tabs.map(\.id) == state.tabs.map(\.id))
    }
}
#endif
