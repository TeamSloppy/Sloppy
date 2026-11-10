import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    func registerComposerReferences(_ references: [ChatComposerReference]) {
        composerDraft.registerReferences(references.map {
            var reference = $0
            if reference.endpoint == nil { reference.endpoint = sessionEndpoint }
            return reference
        })
    }

    public func openSettings(_ destination: ClientSettingsDestination = .general) {
        onOpenSettings(destination)
    }

    public func expandMobileComposerFullscreen() {
        guard isMobileComposerExpanded else { return }
        isMobileComposerFullscreen = true
    }

    public func dismissComposerFocus() {
        updateMobileComposerExpansion(false)
        composerFocusResetToken += 1
    }

    public func requestComposerFocus() {
        composerFocusRequestToken += 1
    }

    public func requestTranscriptScrollToEnd() {
        transcriptScrollToEndRequest &+= 1
    }

    func updateComposerSuggestions(for text: String, cursorOffset: Int? = nil) {
        suggestionTask?.cancel()
        composerSuggestionCursorOffset = cursorOffset
        composerSuggestionRequestID &+= 1
        let requestID = composerSuggestionRequestID
        guard let query = ChatComposerQuery.parse(text, cursorOffset: cursorOffset),
              let agent = selectedAgent else {
            setComposerSuggestions([])
            composerSuggestionState = .hidden
            return
        }
        let scope = composerCatalogScope
        let projectID = activeProjectId
        let key = scope + "|" + String(query.trigger) + query.term
        setComposerSuggestions(composerResultCache.cached(key) ?? localComposerSuggestions(query: query, agentId: agent.id, scope: scope))
        composerSuggestionState = .loading

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let suggestions = try await composerResultCache.load(key) { [self] in
                    try await loadComposerSuggestions(query: query, agentId: agent.id, projectId: projectID, scope: scope)
                }
                guard !Task.isCancelled, composerSuggestionRequestID == requestID, composerCatalogScope == scope else { return }
                registerComposerReferences(suggestions.compactMap(\.reference))
                setComposerSuggestions(suggestions)
                composerSuggestionState = .ready
            } catch {
                guard !Task.isCancelled, composerSuggestionRequestID == requestID, composerCatalogScope == scope else { return }
                composerSuggestionState = .failed(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func moveComposerSuggestionSelection(_ direction: ChatComposerSuggestionSelectionDirection) -> Bool {
        composerSuggestionSelection.move(direction, in: composerSuggestions)
    }

    @discardableResult
    func applySelectedComposerSuggestion() -> Bool {
        guard let suggestion = composerSuggestionSelection.selectedSuggestion(in: composerSuggestions) else {
            return false
        }
        applyComposerSuggestion(suggestion)
        return true
    }

    func applyComposerSuggestion(_ suggestion: ChatComposerSuggestion) {
        guard let query = ChatComposerQuery.parse(
            composerDraft.text,
            cursorOffset: composerSuggestionCursorOffset
        ) else { return }
        let application = query.applying(suggestion, to: composerDraft.text)
        if let reference = suggestion.reference { registerComposerReferences([reference]) }
        composerDraft.text = application.text
        let insertionPoint = composerDraft.text.index(
            composerDraft.text.startIndex,
            offsetBy: application.cursorOffset
        )
        composerDraft.selection = TextSelection(insertionPoint: insertionPoint)
        suggestionTask?.cancel()
        composerSuggestionRequestID &+= 1
        setComposerSuggestions([])
        composerSuggestionState = .hidden
    }

    func retryComposerSuggestions() {
        composerResultCache.invalidate()
        composerCommandCache.invalidate()
        updateComposerSuggestions(for: composerDraft.text, cursorOffset: composerSuggestionCursorOffset)
    }

    func preloadComposerCatalog() async {
        guard let agentID = selectedAgent?.id else { return }
        _ = try? await cachedComposerCommands(agentId: agentID, scope: composerCatalogScope)
    }

    private func cachedComposerCommands(agentId: String, scope: String) async throws -> [AgentChatSlashCommandItem] {
        let key = scope
        let client = apiClient
        return try await composerCommandCache.load(key) {
            try await client.fetchChatSlashCommands(agentId: agentId).commands
        }
    }

    private func setComposerSuggestions(_ suggestions: [ChatComposerSuggestion]) {
        composerSuggestions = suggestions
        composerSuggestionSelection.reconcile(with: suggestions)
    }

    private func localComposerSuggestions(query: ChatComposerQuery, agentId: String, scope: String) -> [ChatComposerSuggestion] {
        let commands = composerCommandCache.cached(scope) ?? []
        if query.trigger == "/" {
            return filterCommands(commands, query: query.term, skillsOnly: false, agentId: agentId)
        }
        guard query.trigger == "@" else { return [] }
        let summaries = ChatSessionCatalog.merge([sessionCatalog, sessions])
            .filter { matches(query.term, in: $0.title) || matches(query.term, in: $0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(8).map(ChatComposerSuggestion.session)
        return Array(summaries) + filterCommands(commands, query: query.term, skillsOnly: true, agentId: agentId)
    }

    private func loadComposerSuggestions(query: ChatComposerQuery, agentId: String, projectId: String?, scope: String) async throws -> [ChatComposerSuggestion] {
        switch query.trigger {
        case "/":
            let commands = try await cachedComposerCommands(agentId: agentId, scope: scope)
            return filterCommands(commands, query: query.term, skillsOnly: false, agentId: agentId)
        case "@":
            async let commands = cachedComposerCommands(agentId: agentId, scope: scope)
            async let files = loadProjectFiles(matching: query.term, projectId: projectId)
            async let sessionResults = apiClient.fetchSessionMentions(query: query.term)
            let skillItems = filterCommands(try await commands, query: query.term, skillsOnly: true, agentId: agentId)
            let sessionItems = (try await sessionResults).sorted { lhs, rhs in
                let lhsLocal = lhs.projectId == projectId
                let rhsLocal = rhs.projectId == projectId
                return lhsLocal == rhsLocal ? lhs.updatedAt > rhs.updatedAt : lhsLocal
            }.prefix(8).map(ChatComposerSuggestion.session)
            return Array(sessionItems) + Array((try await files).prefix(6)) + Array(skillItems.prefix(4))
        case "#":
            guard let projectId else { return [] }
            let project = try await apiClient.fetchProject(id: projectId)
            return (project.tasks ?? [])
                .filter { matches(query.term, in: $0.title) || matches(query.term, in: $0.id) }
                .prefix(12)
                .map {
                    ChatComposerSuggestion(
                        id: "task:\($0.id)", kind: .task, title: $0.title,
                        subtitle: $0.status.replacingOccurrences(of: "_", with: " "), insertion: "#\($0.id)",
                        reference: .init(rawText: "#\($0.id)", title: $0.title, target: .task(projectId: projectId, taskId: $0.id))
                    )
                }
        default:
            return []
        }
    }

    private func filterCommands(
        _ commands: [AgentChatSlashCommandItem],
        query: String,
        skillsOnly: Bool,
        agentId: String
    ) -> [ChatComposerSuggestion] {
        commands
            .filter { !skillsOnly || $0.source == "skill" }
            .filter { matches(query, in: $0.name) || matches(query, in: $0.description) }
            .prefix(12)
            .map {
                let isSkill = $0.source == "skill"
                let prefix = skillsOnly ? "@" : "/"
                return ChatComposerSuggestion(
                    id: "\($0.source):\($0.skillId ?? $0.name)",
                    kind: isSkill ? .skill : .command,
                    title: prefix + $0.name,
                    subtitle: $0.description,
                    insertion: prefix + $0.name,
                    reference: .init(rawText: prefix + $0.name, title: isSkill ? ($0.displayName ?? $0.name) : prefix + $0.name,
                                     detail: [$0.description, $0.argument].compactMap { $0 }.joined(separator: "\n\n"),
                                     target: isSkill ? .skill(agentId: agentId, skillId: $0.skillId ?? $0.name)
                                         : .command(agentId: agentId, name: $0.name))
                )
            }
    }

    private func loadProjectFiles(
        matching query: String,
        projectId: String?
    ) async throws -> [ChatComposerSuggestion] {
        guard let projectId else { return [] }

        do {
            return try await apiClient.searchProjectFiles(
                projectId: projectId,
                query: query,
                limit: 50
            )
            .filter { $0.type == .file }
            .map { projectFileSuggestion(path: $0.path, projectId: projectId) }
        } catch let error as APIError where error.statusCode == 404 {
            return try await loadProjectFilesByWalking(matching: query, projectId: projectId)
        }
    }

    private func loadProjectFilesByWalking(
        matching query: String,
        projectId: String
    ) async throws -> [ChatComposerSuggestion] {
        var pending = [""]
        var results: [ChatComposerSuggestion] = []
        var visitedDirectoryCount = 0
        while let directory = pending.popLast(),
              results.count < 12,
              visitedDirectoryCount < 500,
              !Task.isCancelled {
            visitedDirectoryCount += 1
            let entries = try await apiClient.fetchProjectFiles(projectId: projectId, path: directory)
            for entry in entries {
                let path = directory.isEmpty ? entry.name : "\(directory)/\(entry.name)"
                if entry.type == .directory {
                    pending.append(path)
                } else if matches(query, in: path) {
                    results.append(projectFileSuggestion(path: path, projectId: projectId))
                    if results.count == 12 { break }
                }
            }
        }
        return results
    }

    private func projectFileSuggestion(path: String, projectId: String) -> ChatComposerSuggestion {
        ChatComposerSuggestion(
            id: "file:\(path)",
            kind: .file,
            title: path,
            subtitle: "Project file",
            insertion: "@\(path)",
            reference: .init(rawText: "@\(path)", title: URL(fileURLWithPath: path).lastPathComponent,
                      detail: path, target: .file(projectId: projectId, path: path))
        )
    }

    private func matches(_ query: String, in value: String) -> Bool {
        query.isEmpty || value.localizedCaseInsensitiveContains(query)
    }
}
