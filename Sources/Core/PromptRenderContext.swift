import Foundation
import Protocols

struct PromptRenderContext: Sendable {
    var processKind: PromptProcessKind
    var agentID: String
    var sessionID: String?
    var bootstrapMarker: String?
    var documents: AgentDocumentBundle?
    var installedSkills: [InstalledSkill]

    static func agentSessionBootstrap(
        agentID: String,
        sessionID: String,
        bootstrapMarker: String,
        documents: AgentDocumentBundle,
        installedSkills: [InstalledSkill]
    ) -> PromptRenderContext {
        PromptRenderContext(
            processKind: .agentSessionBootstrap,
            agentID: agentID,
            sessionID: sessionID,
            bootstrapMarker: bootstrapMarker,
            documents: documents,
            installedSkills: installedSkills
        )
    }
}
