import Foundation

/// Parent links are resolved within an instance. Missing parents and cycles remain visible as roots.
public struct ChatSidebarSessionTree: Sendable {
    public let roots: [ChatSessionSummary]
    private let childrenByID: [String: [ChatSessionSummary]]
    private let parentsByID: [String: String]
    private let sessionsByStorageID: [String: ChatSessionSummary]
    private let defaultSourceInstanceID: String?

    public init(sessions: [ChatSessionSummary] = [], pinnedSessionIDs: Set<String> = [], defaultSourceInstanceID: String? = nil) {
        self.defaultSourceInstanceID = defaultSourceInstanceID
        func key(_ session: ChatSessionSummary, id: String? = nil) -> String {
            InstanceScopedID(instanceID: session.sourceInstanceID ?? defaultSourceInstanceID ?? "direct", localID: id ?? session.id).description
        }
        let sorted = sessions.sorted { $0.updatedAt == $1.updatedAt ? $0.storageID < $1.storageID : $0.updatedAt > $1.updatedAt }
        var index: [String: ChatSessionSummary] = [:]
        for session in sorted where index[key(session)] == nil { index[key(session)] = session }
        var parents: [String: String] = [:]
        for session in index.values where !pinnedSessionIDs.contains(session.storageID) {
            guard let parent = session.parentSessionId, index[key(session, id: parent)] != nil else { continue }
            var visited: Set<String> = [key(session)]
            var cursor: ChatSessionSummary? = index[key(session, id: parent)]
            var hasCycle = false
            while let current = cursor {
                if !visited.insert(key(current)).inserted { hasCycle = true; break }
                cursor = current.parentSessionId.flatMap { index[key(current, id: $0)] }
            }
            if !hasCycle { parents[key(session)] = key(session, id: parent) }
        }
        var children: [String: [ChatSessionSummary]] = [:]
        var roots: [ChatSessionSummary] = []
        var seen: Set<String> = []
        for session in sorted where seen.insert(key(session)).inserted {
            if let parent = parents[key(session)] { children[parent, default: []].append(session) }
            else { roots.append(session) }
        }
        self.roots = roots
        childrenByID = children
        parentsByID = parents
        sessionsByStorageID = sorted.reduce(into: [:]) { result, session in result[session.storageID] = session }
    }

    public func children(of session: ChatSessionSummary) -> [ChatSessionSummary] { childrenByID[key(session)] ?? [] }

    public func contains(_ storageID: String?, under parent: ChatSessionSummary) -> Bool {
        guard let storageID, let selected = sessionsByStorageID[storageID] else { return false }
        var cursor = parentsByID[key(selected)]
        while let id = cursor {
            if id == key(parent) { return true }
            cursor = parentsByID[id]
        }
        return false
    }

    private func key(_ session: ChatSessionSummary) -> String {
        InstanceScopedID(instanceID: session.sourceInstanceID ?? defaultSourceInstanceID ?? "direct", localID: session.id).description
    }
}
