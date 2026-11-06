import Foundation
import Protocols

extension SloppyRuntimeHost {
    /// References are discovered from the stored conversation, never supplied as caller file paths.
    public func toolOutputArtifacts(workspaceURL: URL, persistedSessionID: String) throws -> [AgentToolOutputArtifact] {
        let store = AgentSessionFileStore(agentsRootURL: try agentsRootURL(workspaceURL: workspaceURL))
        let artifacts = try store.toolOutputArtifactReferences(agentID: Self.agentID, sessionID: persistedSessionID)
        var seen: Set<String> = []
        return artifacts.compactMap { artifact in
            guard artifact.agentId == Self.agentID,
                  artifact.sessionId == persistedSessionID, seen.insert(artifact.attachment.id).inserted else { return nil }
            return artifact
        }
    }

    private func storedOutput(workspaceURL: URL, sessionID: String, artifactID: String) throws -> (AgentSessionFileStore, AgentToolOutputArtifact) {
        guard let artifact = try toolOutputArtifacts(workspaceURL: workspaceURL, persistedSessionID: sessionID)
            .first(where: { $0.attachment.id == artifactID }) else { throw HostError.runtimeFailure("This output does not belong to the conversation.") }
        return (AgentSessionFileStore(agentsRootURL: try agentsRootURL(workspaceURL: workspaceURL)), artifact)
    }

    public func readToolOutput(workspaceURL: URL, persistedSessionID: String, artifactID: String,
        offset: Int = 0, limit: Int = 65_536) throws -> ToolOutputArtifactChunk {
        let (store, artifact) = try storedOutput(workspaceURL: workspaceURL, sessionID: persistedSessionID, artifactID: artifactID)
        return try store.readToolOutputArtifactChunk(artifact, offset: offset, limit: limit)
    }

    public func exportToolOutput(workspaceURL: URL, persistedSessionID: String, artifactID: String, to destination: URL) throws {
        let (store, artifact) = try storedOutput(workspaceURL: workspaceURL, sessionID: persistedSessionID, artifactID: artifactID)
        try store.exportToolOutputArtifact(artifact, to: destination)
    }

    /// Verify into a private snapshot before yielding. Cancellation closes handles and removes it.
    public func streamToolOutput(workspaceURL: URL, persistedSessionID: String, artifactID: String) throws -> ToolOutputArtifactStream {
        let (store, artifact) = try storedOutput(workspaceURL: workspaceURL, sessionID: persistedSessionID, artifactID: artifactID)
        return try ToolOutputArtifactStream(store: store, artifact: artifact)
    }

    @discardableResult
    public func cleanupToolOutputs(workspaceURL: URL, persistedSessionID: String, olderThan cutoff: Date) throws -> Int {
        let store = AgentSessionFileStore(agentsRootURL: try agentsRootURL(workspaceURL: workspaceURL))
        return try store.cleanupToolOutputArtifacts(agentID: Self.agentID, sessionID: persistedSessionID, olderThan: cutoff)
    }
}
