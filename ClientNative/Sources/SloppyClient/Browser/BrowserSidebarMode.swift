import SwiftUI
import Observation

enum BrowserSidebarMode: String, CaseIterable, Identifiable {
    case sites, time, tasks, notes
    var id: String { rawValue }
    var title: String {
        switch self { case .sites: "Sites"; case .time: "Time & Focus"; case .tasks: "Tasks"; case .notes: "Notes" }
    }
    var icon: String {
        switch self { case .sites: "globe"; case .time: "timer"; case .tasks: "checklist"; case .notes: "note.text" }
    }
    var shortcut: Character {
        switch self { case .sites: "1"; case .time: "2"; case .tasks: "3"; case .notes: "4" }
    }
}

extension EnvironmentValues {
    @Entry var browserSidebarLayout = false
}

@Observable @MainActor
final class BrowserSidebarDrafts {
    var taskQuery = ""
    var taskTitle = ""
    var newTask: BrowserPersonalTask?
    var taskFilter = BrowserTaskFilter.all
    var timeWeek = false
    var timeSite = ""
    var noteQuery = ""
    var noteSelection: UUID?
    var notePreview = false
}
