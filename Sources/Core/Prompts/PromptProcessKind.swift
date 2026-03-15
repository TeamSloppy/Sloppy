import Foundation

enum PromptProcessKind: String, Sendable {
    case agentSessionBootstrap = "agent_session_bootstrap"
    case swarmPlanner = "swarm_planner"

    var templateName: String {
        rawValue
    }
}
