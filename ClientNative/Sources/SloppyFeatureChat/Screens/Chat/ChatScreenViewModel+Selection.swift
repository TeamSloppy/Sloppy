import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func pickAgent(_ agent: APIAgentRecord) {
        switchAgent(agent)
    }

    public func pickModel(_ model: ChatModelOption) {
        selectedModelId = model.id
        selectedReasoningEffort = .default
        if let agentId = selectedAgent?.id {
            modelPreferences.setSelection(
                model.id,
                server: apiClient.endpoint.cacheNamespace,
                agentId: agentId,
                sessionId: selectedSessionId
            )
        }
    }

    public func pickReasoningEffort(_ effort: ChatReasoningEffort) {
        selectedReasoningEffort = effort
    }

    public func refreshAvailableModels() async {
        do {
            applyAvailableModels(try await apiClient.fetchAvailableModels())
        } catch {
            showSessionStatus("Couldn’t refresh models: \(error.localizedDescription)")
        }
    }

    public func pickSession(_ session: ChatSessionSummary) {
        openSession(session)
    }

    public func pickNewSession() {
        startNewSession()
    }

    public func startNewMessage() {
        guard let agent = selectedAgent ?? agents.first else { return }

        guard let projectId = activeProjectId else {
            activateDraft(agent: agent, contextTitle: nil)
            return
        }

        let projectName = projects.first(where: { $0.id == projectId })?.name
        let contextTitle = projectName.map { "Project: \($0)" } ?? activeContextTitle
        activateProjectContext(
            agent: agent,
            projectId: projectId,
            contextTitle: contextTitle ?? "Project",
            preferredSessionTitle: nil,
            preferredTaskId: nil,
            opensPreferredSession: false
        )
        createsSeparateProjectChat = true
    }

    public func startNewMessage(agentID: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        activateDraft(agent: agent, contextTitle: nil)
    }

    /// Releases a detached presentation's current session without cancelling delivery.
    public func closeSession() {
#if os(macOS)
        quoteAnnotationPresenter.close()
#endif
        if let id = editingComposerQuoteID { finishComposerQuoteEditing(id: id) }
        pendingSessionSummary = nil
        pendingNavigationRequest = nil
        saveActiveComposerDraft()
        disconnectCurrentSession()
        selectedSessionId = nil
        selectedAgent = nil
        activeContextTitle = nil
        activeProjectId = nil
        activeTaskId = nil
        transcript.clear()
    }

    public func pickPersonal() {
        pendingNavigationRequest = nil
        settings.lastProjectId = nil
        settings.lastSessionId = nil
        routeToBlankChat()
    }

    public func pickProject(_ project: APIProjectRecord) {
        guard let agent = selectedAgent ?? agents.first else { return }
        activateProjectContext(
            agent: agent,
            projectId: project.id,
            contextTitle: "Project: \(project.name)",
            preferredSessionTitle: nil,
            preferredTaskId: nil,
            opensPreferredSession: true
        )
    }

    public func useStarterPrompt(_ prompt: String) {
        composerDraft.text = prompt
        saveActiveComposerDraft()
    }

    public func addTextSelectionToComposer(_ selectedText: String) {
        let selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }

        applyComposerTextMutation(.append(selectedText))
    }

    public func addQuoteToComposer(_ selectedText: String) {
        let selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }

        let quote = ChatComposerQuote(text: selectedText)
        if activeComposerDraftKey == nil {
            pendingComposerQuotes.append(quote)
        }
        composerQuotes.append(quote)
        saveActiveComposerDraft()
        dismissComposerFocus()
    }

    /// The browser binds its menu to this exact draft, not whichever chat is selected later.
    public func makeBrowserTextAnnotationReceiver() -> @MainActor (ChatComposerQuote) -> Bool {
        let draftKey = activeComposerDraftKey
        let sessionID = selectedSessionId
        let agentID = selectedAgent?.id
        let endpoint = sessionEndpoint
        return { [weak self] quote in
            guard let self, activeComposerDraftKey == draftKey, selectedSessionId == sessionID,
                  selectedAgent?.id == agentID, sessionEndpoint == endpoint,
                  let source = quote.browserSource, ["http", "https"].contains(source.url.scheme?.lowercased() ?? ""),
                  source.url.host != nil, !quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  quote.text.utf16.count <= 12000 else { return false }
            if activeComposerDraftKey == nil { pendingComposerQuotes.append(quote) }
            composerQuotes.append(quote)
            saveActiveComposerDraft()
            requestComposerFocus()
            return true
        }
    }

    public func updateComposerQuote(id: ChatComposerQuote.ID, comment: String) {
        guard let index = composerQuotes.firstIndex(where: { $0.id == id }) else { return }
        composerQuotes[index].comment = comment
        if let pendingIndex = pendingComposerQuotes.firstIndex(where: { $0.id == id }) {
            pendingComposerQuotes[pendingIndex].comment = comment
        }
        saveActiveComposerDraft()
    }

    public func updateImageAnnotations(id: ChatComposerAttachment.ID, annotations: [ChatImageAnnotation]) {
        guard let index = composerAttachments.firstIndex(where: { $0.id == id }) else { return }
        if annotations.isEmpty, !composerAttachments[index].annotations.isEmpty,
           composerAttachments[index].annotations.allSatisfy({ $0.browserSource != nil }) {
            removeComposerAttachment(id: id)
            return
        }
        composerAttachments[index].annotations = annotations
        saveActiveComposerDraft()
    }

    func updateImageEdits(_ attachment: ChatComposerAttachment) {
        guard let index = composerAttachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        guard attachment.sizeBytes <= Self.maximumAttachmentSize else {
            sendErrorMessage = "The marked-up image is larger than 25 MB"
            return
        }
        composerAttachments[index].markup = attachment.markup
        if attachment.markup != nil {
            composerAttachments[index].annotations = attachment.annotations
            saveActiveComposerDraft()
        } else {
            updateImageAnnotations(id: attachment.id, annotations: attachment.annotations)
        }
    }

    public func removeComposerQuote(id: ChatComposerQuote.ID) {
#if os(macOS)
        quoteAnnotationPresenter.anchors.removeValue(forKey: id)
        if editingComposerQuoteID == id { quoteAnnotationPresenter.close() }
#endif
        if editingComposerQuoteID == id { editingComposerQuoteID = nil }
        composerQuotes.removeAll { $0.id == id }
        pendingComposerQuotes.removeAll { $0.id == id }
        saveActiveComposerDraft()
    }

    func finishComposerQuoteEditing(id: UUID) {
        if editingComposerQuoteID == id { editingComposerQuoteID = nil }
        guard let quote = composerQuotes.first(where: { $0.id == id }) else { return }
        let comment = quote.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if comment.isEmpty { removeComposerQuote(id: id) }
        else { updateComposerQuote(id: id, comment: comment) }
    }

#if !os(macOS)
    func editComposerQuote(id: UUID) -> Bool { false }
#endif

    public func insertCodeBlock() {
        let text = composerDraft.text
        let range = ChatComposerNativeSelection.nativeRange(
            from: composerDraft.selection,
            in: text
        ).flatMap { Range($0, in: text) } ?? text.endIndex..<text.endIndex
        let selectedText = String(text[range])
        let needsLeadingNewline = range.lowerBound > text.startIndex
            && text[text.index(before: range.lowerBound)] != "\n"
        let needsTrailingNewline = range.upperBound < text.endIndex
            && text[range.upperBound] != "\n"
        let leadingNewline = needsLeadingNewline ? "\n" : ""
        let trailingNewline = needsTrailingNewline ? "\n" : ""
        let replacement = "\(leadingNewline)```\n\(selectedText)\n```\(trailingNewline)"
        let cursorOffset = text.distance(from: text.startIndex, to: range.lowerBound)
            + leadingNewline.count + 4 + selectedText.count
        composerDraft.text = text.replacingCharacters(in: range, with: replacement)
        let cursor = composerDraft.text.index(composerDraft.text.startIndex, offsetBy: cursorOffset)
        composerDraft.selection = TextSelection(insertionPoint: cursor)
        saveActiveComposerDraft()
        requestComposerFocus()
    }

    public func askForMoreDetails(about selectedText: String) {
        let selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }

        applyComposerTextMutation(.replace("Tell me more about this:\n\n\(selectedText)"))
    }

    func applyComposerTextMutation(_ mutation: PendingComposerTextMutation) {
        if activeComposerDraftKey == nil {
            pendingComposerTextMutation = mutation
        }

        switch mutation {
        case .append(let text):
            composerDraft.text = composerDraft.text.isEmpty
                ? text
                : "\(composerDraft.text)\n\(text)"
        case .replace(let text):
            composerDraft.text = text
        }
        saveActiveComposerDraft()
        requestComposerFocus()
    }
}
