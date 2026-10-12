import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    func displayTitle(for session: ChatSessionSummary) -> String {
        session.displayTitle.isEmpty ? "Chat" : session.displayTitle
    }

    func taskSessionTitle(for taskId: String) -> String {
        "task-\(taskId)"
    }

    func sortSessions(_ sessions: [ChatSessionSummary]) -> [ChatSessionSummary] {
        sessions.sorted { lhs, rhs in
            let lhsPinned = settings.isSessionPinned(lhs.storageID)
            let rhsPinned = settings.isSessionPinned(rhs.storageID)
            if lhsPinned != rhsPinned {
                return lhsPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func upsertSessionSummary(_ summary: ChatSessionSummary) {
        sessions.removeAll { $0.storageID == summary.storageID }
        sessions.append(summary)
        sessions = sortSessions(sessions)

        sessionCatalog.removeAll { $0.storageID == summary.storageID }
        sessionCatalog.append(summary)
        sessionCatalog = sortSessions(sessionCatalog)
        onSessionSummaryChange(summary)
    }

    public func mergeSessionSummary(_ summary: ChatSessionSummary) {
        upsertSessionSummary(summary)
    }

    func debugSessionFilePathURL(for session: ChatSessionSummary) -> URL {
        var components = URLComponents(url: apiClient.baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        let agentId = session.agentId
        components.path = "/v1/debug/session-file-path/\(Self.urlPathEscape(agentId))/\(Self.urlPathEscape(session.id))"
        components.queryItems = nil
        return components.url ?? apiClient.baseURL
    }

    private static func urlPathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    func preferredSession(
        in sessions: [ChatSessionSummary],
        title: String?,
        taskId: String? = nil,
        projectId: String? = nil,
        allowsFallback: Bool = true
    ) -> ChatSessionSummary? {
        let candidates = sessions
            .filter { $0.kind != "heartbeat" }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let taskId = taskId?.trimmingCharacters(in: .whitespacesAndNewlines), !taskId.isEmpty {
            var normalizedTaskTitles = [taskSessionTitle(for: taskId)]
            if let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !projectId.isEmpty {
                normalizedTaskTitles.append("task-comment:\(projectId):\(taskId)")
            }
            normalizedTaskTitles = normalizedTaskTitles.map { $0.lowercased() }

            if let taskSession = candidates.first(where: { session in
                session.taskId?.caseInsensitiveCompare(taskId) == .orderedSame
                    || normalizedTaskTitles.contains(session.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }) {
                return taskSession
            }
        }

        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return allowsFallback ? candidates.first : nil
        }

        let normalizedTitle = title.lowercased()
        let titleMatch = candidates.first {
            let sessionTitle = $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return sessionTitle == normalizedTitle || sessionTitle.contains(normalizedTitle)
        }

        return titleMatch ?? (allowsFallback ? candidates.first : nil)
    }

    func showSessionStatus(_ status: String) {
        sessionStatusTask?.cancel()
        sessionActionStatus = status
        sessionStatusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                sessionActionStatus = nil
            }
        }
    }

    #if DEBUG
    func saveDebugSessionData(_ data: Data, session: ChatSessionSummary) throws -> URL {
        let fileManager = FileManager.default
        let fileName = "sloppy-session-\(safeFileName(displayTitle(for: session)))-\(session.id).json"
        let searchDirectories: [FileManager.SearchPathDirectory] = [
            .downloadsDirectory,
            .documentDirectory,
        ]

        var lastError: Error?
        for directory in searchDirectories {
            do {
                let directoryURL = try fileManager.url(
                    for: directory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let fileURL = directoryURL.appendingPathComponent(fileName)
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(sanitizedScalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "chat" : String(collapsed.prefix(48))
    }
    #endif
}
