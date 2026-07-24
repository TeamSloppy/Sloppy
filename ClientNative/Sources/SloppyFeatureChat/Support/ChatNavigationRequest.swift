public struct ChatNavigationRequest: Equatable, Sendable {
    public enum Context: Equatable, Sendable {
        case blank
        case project(projectId: String, projectName: String, agentId: String?)
        case task(projectId: String, projectName: String, taskId: String, taskTitle: String, agentId: String?)
    }

    public var id: Int
    public var context: Context
    public var opensPreferredSession: Bool

    public init(
        id: Int,
        context: Context,
        opensPreferredSession: Bool = true
    ) {
        self.id = id
        self.context = context
        self.opensPreferredSession = opensPreferredSession
    }

    public var preferredAgentId: String? {
        switch context {
        case .blank:
            return nil
        case .project(_, _, let agentId):
            return agentId
        case .task(_, _, _, _, let agentId):
            return agentId
        }
    }

    public var title: String? {
        switch context {
        case .blank:
            return nil
        case .project(_, let projectName, _):
            return projectName
        case .task(_, _, _, let taskTitle, _):
            return taskTitle
        }
    }
}
