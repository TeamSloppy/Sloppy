import Foundation

public enum AppRoute: String, CaseIterable, Hashable, Identifiable, Sendable {
    case overview
    case projects
    case agents
    case tasks
    case review

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .agents: "Agents"
        case .tasks: "Tasks"
        case .review: "Review"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .projects: "folder"
        case .agents: "person.2"
        case .tasks: "checklist"
        case .review: "eye"
        }
    }
}
