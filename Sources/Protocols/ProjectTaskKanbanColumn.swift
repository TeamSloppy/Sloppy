/// Board grouping shared by all task status mutations, including workers and task sync.
enum ProjectTaskKanbanColumn {
    case todo, inProgress, needsReview, done, other

    init(status: String) {
        switch status {
        case "todo", "backlog", "ready": self = .todo
        case "in_progress": self = .inProgress
        case "needs_review": self = .needsReview
        case "done": self = .done
        default: self = .other
        }
    }
}
