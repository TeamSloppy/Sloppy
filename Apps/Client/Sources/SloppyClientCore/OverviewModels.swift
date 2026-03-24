import Foundation

public struct OverviewData: Sendable, Equatable {
    public var projects: [ProjectSummary]
    public var agents: [AgentOverview]
    public var activeTasks: Int
    public var completedTasks: Int

    public init(
        projects: [ProjectSummary] = [],
        agents: [AgentOverview] = [],
        activeTasks: Int = 0,
        completedTasks: Int = 0
    ) {
        self.projects = projects
        self.agents = agents
        self.activeTasks = activeTasks
        self.completedTasks = completedTasks
    }
}

public struct ProjectSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var channelCount: Int
    public var taskCount: Int
    public var activeTaskCount: Int

    public init(
        id: String,
        name: String,
        description: String = "",
        channelCount: Int = 0,
        taskCount: Int = 0,
        activeTaskCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.channelCount = channelCount
        self.taskCount = taskCount
        self.activeTaskCount = activeTaskCount
    }
}

public struct AgentOverview: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var role: String

    public init(id: String, displayName: String, role: String = "") {
        self.id = id
        self.displayName = displayName
        self.role = role
    }
}

public struct APIProjectRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var channels: [APIProjectChannel]?
    public var tasks: [APIProjectTask]?
    public var actors: [String]?
    public var teams: [String]?

    public init(
        id: String,
        name: String,
        description: String = "",
        channels: [APIProjectChannel]? = nil,
        tasks: [APIProjectTask]? = nil,
        actors: [String]? = nil,
        teams: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.channels = channels
        self.tasks = tasks
        self.actors = actors
        self.teams = teams
    }
}

public struct APIProjectChannel: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var channelId: String

    public init(id: String, title: String, channelId: String) {
        self.id = id
        self.title = title
        self.channelId = channelId
    }
}

public struct APIProjectTask: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: String
    public var priority: String?
    public var actorId: String?

    public init(id: String, title: String, status: String, priority: String? = nil, actorId: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.actorId = actorId
    }
}

public struct APIAgentRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var role: String
    public var isSystem: Bool?

    public init(id: String, displayName: String, role: String = "", isSystem: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.isSystem = isSystem
    }
}

public struct APIAgentTaskRecord: Codable, Sendable, Identifiable {
    public var projectId: String
    public var projectName: String
    public var task: APIProjectTask

    public var id: String { "\(projectId)/\(task.id)" }

    public init(projectId: String, projectName: String, task: APIProjectTask) {
        self.projectId = projectId
        self.projectName = projectName
        self.task = task
    }
}

private let activeStatuses: Set<String> = ["in_progress", "ready", "needs_review"]

public extension APIProjectRecord {
    func toSummary() -> ProjectSummary {
        let allTasks = tasks ?? []
        let active = allTasks.filter { activeStatuses.contains($0.status) }
        return ProjectSummary(
            id: id,
            name: name,
            description: description,
            channelCount: channels?.count ?? 0,
            taskCount: allTasks.count,
            activeTaskCount: active.count
        )
    }
}

public extension APIAgentRecord {
    func toOverview() -> AgentOverview {
        AgentOverview(id: id, displayName: displayName, role: role)
    }
}
