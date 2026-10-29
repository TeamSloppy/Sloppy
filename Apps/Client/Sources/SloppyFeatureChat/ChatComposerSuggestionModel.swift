import Foundation
import Observation
import SloppyClientCore

@Observable
@MainActor
final class ChatComposerSuggestionModel {
    var suggestions: [ChatComposerSuggestion] = []
    var selection = ChatComposerSuggestionSelection()
    var isLoading = false
    var error: String?
    private var request: Task<Void, Never>?
    private var generation = 0
    private var activeQuery: ChatComposerQuery?

    func dismiss() {
        generation += 1
        request?.cancel()
        activeQuery = nil
        suggestions = []
        selection.reconcile(with: [])
        error = nil
        isLoading = false
    }

    func update(text: String, cursor: Int?, agentID: String?, projectID: String?, api: SloppyAPIClient) {
        dismiss()
        guard let query = ChatComposerQuery.parse(text, cursorOffset: cursor), let agentID else { return }
        activeQuery = query
        isLoading = true
        let current = generation
        request = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                let results = try await load(query, agentID: agentID, projectID: projectID, api: api)
                guard !Task.isCancelled, current == generation else { return }
                suggestions = results
                selection.reconcile(with: results)
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func apply(_ suggestion: ChatComposerSuggestion, text: String) -> String {
        guard let query = activeQuery else { return text }
        let updated = query.applying(suggestion, to: text).text
        dismiss()
        return updated
    }

    private func load(_ query: ChatComposerQuery, agentID: String, projectID: String?, api: SloppyAPIClient) async throws -> [ChatComposerSuggestion] {
        switch query.trigger {
        case "/":
            return commands(try await api.fetchChatSlashCommands(agentId: agentID).commands, term: query.term, skills: false)
        case "@":
            // Each source has its own failure state; a failed session endpoint must not hide files.
            async let commandResult = capture { try await api.fetchChatSlashCommands(agentId: agentID).commands }
            async let sessionResult = capture { try await api.fetchSessionMentions(query: query.term) }
            async let fileResult = capture {
                if let projectID { return try await api.workspace.searchFiles(projectID: projectID, term: query.term) }
                return [ProjectFileSearchEntry]()
            }
            let (commandData, sessionData, fileData) = await (commandResult, sessionResult, fileResult)
            try Task.checkCancellation()
            error = [commandData.error, sessionData.error, fileData.error].compactMap { $0 }.joined(separator: " · ")
            let sessions = sessionData.values.sorted {
                let lhsLocal = $0.projectId == projectID
                let rhsLocal = $1.projectId == projectID
                return lhsLocal == rhsLocal ? $0.updatedAt > $1.updatedAt : lhsLocal
            }.prefix(8).map(ChatComposerSuggestion.session)
            let files = fileData.values.filter { $0.type == .file }.prefix(6).map {
                ChatComposerSuggestion(id: "file:\($0.path)", kind: .file, title: $0.path, subtitle: "Project file", insertion: "@\($0.path)")
            }
            return Array(files) + Array(sessions) + Array(commands(commandData.values, term: query.term, skills: true).prefix(4))
        case "#":
            guard let projectID else { return [] }
            return (try await api.fetchProject(id: projectID).tasks ?? []).filter {
                matches(query.term, $0.title) || matches(query.term, $0.id)
            }.prefix(12).map {
                ChatComposerSuggestion(id: "task:\($0.id)", kind: .task, title: $0.title, subtitle: $0.status.replacingOccurrences(of: "_", with: " "), insertion: "#\($0.id)")
            }
        default: return []
        }
    }

    private func capture<T: Sendable>(_ operation: () async throws -> [T]) async -> (values: [T], error: String?) {
        do { return (try await operation(), nil) }
        catch { return ([], error.localizedDescription) }
    }

    private func commands(_ items: [AgentChatSlashCommandItem], term: String, skills: Bool) -> [ChatComposerSuggestion] {
        items.filter { !skills || $0.source == "skill" }.filter { matches(term, $0.name) || matches(term, $0.description) }.prefix(12).map {
            let prefix = skills ? "@" : "/"
            return ChatComposerSuggestion(id: "\($0.source):\($0.skillId ?? $0.name)", kind: $0.source == "skill" ? .skill : .command,
                title: prefix + $0.name, subtitle: $0.description, insertion: prefix + $0.name)
        }
    }
    private func matches(_ term: String, _ text: String) -> Bool { term.isEmpty || text.localizedCaseInsensitiveContains(term) }
}
