import Foundation
import SloppyClientCore

extension WorkspaceBrowserSession {
    func executeOrganizer(_ name: String, input: WorkspaceBrowserCommand.Input) throws -> WorkspaceBrowserPage {
        guard let workspace, workspace.isBrowsing,
              let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title.count <= 512, (input.text?.utf8.count ?? 0) <= 65536 else {
            throw WorkspaceBrowserRuntimeError.invalidArguments
        }
        let source: URL?
        if let raw = input.url {
            guard let url = BrowserSearchEngine.websiteURL(URL(string: raw)) else { throw WorkspaceBrowserRuntimeError.invalidURL }
            source = url
        } else { source = workspace.selectedTab?.url }
        let id: UUID
        let kind: String
        switch name {
        case "create_note":
            id = workspace.organizer.createNote(pageURL: source)
            workspace.organizer.updateNote(id) { $0.title = title; $0.body = input.text ?? "" }
            kind = "note"
        case "create_todo":
            let due: Date?
            if let raw = input.dueAt {
                let format = ISO8601DateFormatter()
                format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fractional = format.date(from: raw)
                format.formatOptions = [.withInternetDateTime]
                guard let date = fractional ?? format.date(from: raw) else { throw WorkspaceBrowserRuntimeError.invalidArguments }
                due = date
            } else { due = nil }
            let priority: BrowserPersonalTask.Priority
            switch input.priority ?? "normal" {
            case "normal": priority = .normal
            case "low": priority = .low
            case "high": priority = .high
            default: throw WorkspaceBrowserRuntimeError.invalidArguments
            }
            let task = BrowserPersonalTask(title: title, details: input.text ?? "", dueAt: due, priority: priority, pageURL: source)
            guard workspace.organizer.saveTask(task) else { throw WorkspaceBrowserRuntimeError.invalidArguments }
            id = task.id
            kind = "todo"
        default: throw WorkspaceBrowserRuntimeError.invalidArguments
        }
        var result = workspaceSnapshot(workspace)
        result.createdEntry = .init(kind: kind, id: id.uuidString, title: title)
        return result
    }
}
