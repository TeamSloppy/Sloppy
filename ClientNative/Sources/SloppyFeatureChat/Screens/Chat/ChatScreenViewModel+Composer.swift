import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
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
            return
        }

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let suggestions = await loadComposerSuggestions(query: query, agentId: agent.id)
            guard !Task.isCancelled, composerSuggestionRequestID == requestID else { return }
            setComposerSuggestions(suggestions)
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
        composerDraft.text = application.text
        let insertionPoint = composerDraft.text.index(
            composerDraft.text.startIndex,
            offsetBy: application.cursorOffset
        )
        composerDraft.selection = TextSelection(insertionPoint: insertionPoint)
        setComposerSuggestions([])
    }

    private func setComposerSuggestions(_ suggestions: [ChatComposerSuggestion]) {
        composerSuggestions = suggestions
        composerSuggestionSelection.reconcile(with: suggestions)
    }

    private func loadComposerSuggestions(query: ChatComposerQuery, agentId: String) async -> [ChatComposerSuggestion] {
        switch query.trigger {
        case "/":
            let response = try? await apiClient.fetchChatSlashCommands(agentId: agentId)
            return filterCommands(response?.commands ?? [], query: query.term, skillsOnly: false)
        case "@":
            async let commands = try? await apiClient.fetchChatSlashCommands(agentId: agentId)
            async let files = loadProjectFiles(matching: query.term, projectId: activeProjectId)
            async let sessionResults = try? apiClient.fetchSessionMentions(query: query.term)
            let skillItems = filterCommands((await commands)?.commands ?? [], query: query.term, skillsOnly: true)
            let sessionItems = ((await sessionResults) ?? []).sorted { lhs, rhs in
                let lhsLocal = lhs.projectId == activeProjectId
                let rhsLocal = rhs.projectId == activeProjectId
                return lhsLocal == rhsLocal ? lhs.updatedAt > rhs.updatedAt : lhsLocal
            }.prefix(8).map(ChatComposerSuggestion.session)
            return Array(sessionItems) + Array((await files).prefix(6)) + Array(skillItems.prefix(4))
        case "#":
            guard let projectId = activeProjectId,
                  let project = try? await apiClient.fetchProject(id: projectId) else { return [] }
            return (project.tasks ?? [])
                .filter { matches(query.term, in: $0.title) || matches(query.term, in: $0.id) }
                .prefix(12)
                .map {
                    ChatComposerSuggestion(
                        id: "task:\($0.id)", kind: .task, title: $0.title,
                        subtitle: $0.status.replacingOccurrences(of: "_", with: " "), insertion: "#\($0.id)"
                    )
                }
        default:
            return []
        }
    }

    private func filterCommands(
        _ commands: [AgentChatSlashCommandItem],
        query: String,
        skillsOnly: Bool
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
                    insertion: prefix + $0.name
                )
            }
    }

    private func loadProjectFiles(
        matching query: String,
        projectId: String?
    ) async -> [ChatComposerSuggestion] {
        guard let projectId else { return [] }

        do {
            return try await apiClient.searchProjectFiles(
                projectId: projectId,
                query: query,
                limit: 50
            )
            .filter { $0.type == .file }
            .map { projectFileSuggestion(path: $0.path) }
        } catch let error as APIError where error.statusCode == 404 {
            return await loadProjectFilesByWalking(matching: query, projectId: projectId)
        } catch {
            return []
        }
    }

    private func loadProjectFilesByWalking(
        matching query: String,
        projectId: String
    ) async -> [ChatComposerSuggestion] {
        var pending = [""]
        var results: [ChatComposerSuggestion] = []
        var visitedDirectoryCount = 0
        while let directory = pending.popLast(),
              results.count < 12,
              visitedDirectoryCount < 500,
              !Task.isCancelled {
            visitedDirectoryCount += 1
            guard let entries = try? await apiClient.fetchProjectFiles(projectId: projectId, path: directory) else { continue }
            for entry in entries {
                let path = directory.isEmpty ? entry.name : "\(directory)/\(entry.name)"
                if entry.type == .directory {
                    pending.append(path)
                } else if matches(query, in: path) {
                    results.append(projectFileSuggestion(path: path))
                    if results.count == 12 { break }
                }
            }
        }
        return results
    }

    private func projectFileSuggestion(path: String) -> ChatComposerSuggestion {
        ChatComposerSuggestion(
            id: "file:\(path)",
            kind: .file,
            title: path,
            subtitle: "Project file",
            insertion: "@\(path)"
        )
    }

    private func matches(_ query: String, in value: String) -> Bool {
        query.isEmpty || value.localizedCaseInsensitiveContains(query)
    }
}
