import Foundation
import Observation
import SloppyClientCore

enum MainContentMode: String {
    case coding
    case workspace
}

private struct CanvasWorkspaceTarget: Equatable {
    var workspaceID: String?
    var projectID: String?
    var projectName: String?
}

@Observable
@MainActor
final class CanvasWorkspaceViewModel {
    private static let defaultAPIBaseURL = URL(string: "http://localhost:25101")!
    private static let defaultDashboardBaseURL = URL(string: "http://localhost:25102")!
    static let personalWorkspaceName = "Personal"

    private let apiClient: SloppyAPIClient
    private let apiBaseURL: URL
    private let dashboardBaseURL: URL
    private var target: CanvasWorkspaceTarget?
    private var resolutionID = UUID()
    @ObservationIgnored private var socketManager: SessionSocketManager?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var streamedSessionID: String?

    private(set) var projects: [APIProjectRecord] = []
    private(set) var workspaces: [CanvasWorkspaceSummary] = []
    private(set) var selectedWorkspaceID: String?
    private(set) var suggestedWorkspaceID: String?
    private(set) var projectID: String?
    private(set) var projectName: String?
    private(set) var url: URL?
    private(set) var title = "Workspaces"
    private(set) var isResolving = false
    private(set) var libraryError: String?
    private(set) var pageReloadToken = 0
    private(set) var document: CanvasWorkspaceDocument?
    private(set) var agents: [APIAgentRecord] = []
    private(set) var selectedAgentID: String?
    private(set) var activeSessionID: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var widgetHTML: [String: String] = [:]
    private(set) var isLoadingDocument = false
    private(set) var isSendingPrompt = false
    private(set) var editorStatus = "Ready"
    private(set) var streamingMessageID: String?
    private(set) var chatScrollToken = 0
    var isInspectorPresented = true
    var isLayersPanelPresented = true
    var isMiniMapPresented = true
    var selectedElementID: String?
    var isLoadingPage = false
    var pageError: String?

    var isShowingLibrary: Bool {
        selectedWorkspaceID == nil
    }

    var libraryTitle: String {
        projectID == nil ? "Personal Workspaces" : "Project Workspaces"
    }

    var librarySubtitle: String {
        if let projectName {
            return "Canvases in \(projectName)"
        }
        if projectID != nil {
            return "Canvases in the current project"
        }
        return "Canvases in \(Self.personalWorkspaceName)"
    }

    init(
        baseURL: URL? = nil,
        dashboardBaseURL: URL? = nil,
        apiClient: SloppyAPIClient? = nil
    ) {
        let resolvedAPIBaseURL = baseURL ?? apiClient?.baseURL ?? Self.defaultAPIBaseURL
        self.apiClient = apiClient ?? SloppyAPIClient(baseURL: resolvedAPIBaseURL)
        self.apiBaseURL = resolvedAPIBaseURL
        self.dashboardBaseURL = dashboardBaseURL ?? Self.defaultDashboardBaseURL
    }

    func resolve(
        workspaceID: String?,
        projectID: String?,
        projectName: String? = nil,
        force: Bool = false
    ) async {
        let normalizedProjectID = Self.normalized(projectID)
        let nextTarget = CanvasWorkspaceTarget(
            workspaceID: Self.normalized(workspaceID),
            projectID: normalizedProjectID,
            projectName: normalizedProjectID == nil ? nil : Self.normalized(projectName)
        )
        guard force || target != nextTarget else {
            return
        }

        target = nextTarget
        self.projectID = nextTarget.projectID
        self.projectName = nextTarget.projectName
        suggestedWorkspaceID = nextTarget.workspaceID
        showLibrary()
        await refreshLibrary()
    }

    func refreshLibrary() async {
        let requestID = UUID()
        resolutionID = requestID
        isResolving = true
        libraryError = nil
        defer {
            if resolutionID == requestID {
                isResolving = false
            }
        }

        var errors: [String] = []

        do {
            projects = try await apiClient.fetchProjects()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let projectID,
               let selectedProject = projects.first(where: { $0.id == projectID }) {
                projectName = selectedProject.name
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        do {
            let requestedProjectID = projectID
            let records = try await apiClient.fetchCanvasWorkspaces(projectId: requestedProjectID)
                .filter { !$0.isArchived }
                .filter { requestedProjectID != nil || $0.projectId == nil }
                .sorted { $0.updatedAt > $1.updatedAt }
            guard resolutionID == requestID else {
                return
            }
            workspaces = records
        } catch {
            errors.append(error.localizedDescription)
        }

        guard resolutionID == requestID else {
            return
        }
        libraryError = errors.first
    }

    func selectProject(_ project: APIProjectRecord?) async {
        let nextProjectID = project?.id
        guard projectID != nextProjectID else {
            return
        }

        projectID = nextProjectID
        projectName = project?.name
        target = CanvasWorkspaceTarget(
            workspaceID: nil,
            projectID: nextProjectID,
            projectName: project?.name
        )
        suggestedWorkspaceID = nil
        showLibrary()
        await refreshLibrary()
    }

    @discardableResult
    func createWorkspace(title: String, description: String?) async throws -> CanvasWorkspaceSummary {
        let workspace = try await apiClient.createCanvasWorkspace(
            title: title,
            description: Self.normalized(description),
            projectId: projectID
        )
        workspaces = ([workspace] + workspaces.filter { $0.id != workspace.id })
            .sorted { $0.updatedAt > $1.updatedAt }
        openWorkspace(workspace)
        return workspace
    }

    func openWorkspace(_ workspace: CanvasWorkspaceSummary) {
        selectedWorkspaceID = workspace.id
        title = workspace.title
        pageError = nil
        isLoadingPage = false
        url = Self.workspaceURL(
            baseURL: dashboardBaseURL,
            apiBaseURL: apiBaseURL,
            workspaceID: workspace.id
        )
        Task {
            await loadNativeEditor()
        }
    }

    func showLibrary() {
        selectedWorkspaceID = nil
        url = nil
        title = libraryTitle
        pageError = nil
        isLoadingPage = false
        document = nil
        activeSessionID = nil
        messages = []
        streamingMessageID = nil
        stopSessionStream()
    }

    func retry() async {
        pageError = nil
        if selectedWorkspaceID != nil {
            pageReloadToken += 1
        } else {
            await refreshLibrary()
        }
    }

    func currentAccessToken() async -> String? {
        await apiClient.currentAccessToken()
    }

    func selectAgent(_ id: String) {
        selectedAgentID = id
    }

    func loadNativeEditor() async {
        guard let workspaceID = selectedWorkspaceID else { return }
        isLoadingDocument = true
        pageError = nil
        defer { isLoadingDocument = false }
        do {
            async let nextDocument = apiClient.fetchCanvasWorkspaceDocument(workspaceId: workspaceID)
            async let nextAgents = apiClient.fetchAgents()
            document = try await nextDocument
            agents = try await nextAgents.filter { $0.isSystem != true }
            if selectedAgentID == nil {
                selectedAgentID = agents.first?.id
            }
            await loadWidgetArtifacts()
        } catch {
            pageError = error.localizedDescription
        }
    }

    func addElement(_ kind: CanvasWorkspaceElementKind) async {
        guard let document else { return }
        let offset = Double(document.elements.count % 8) * 28
        let size: (Double, Double) = switch kind {
        case .frame: (520, 340)
        case .table, .widget: (360, 240)
        case .text: (280, 120)
        default: (220, 160)
        }
        let text = kind == .sticky ? "New idea" : kind == .frame ? "Frame" : "New \(kind.rawValue)"
        let element = CanvasWorkspaceElement(
            id: "el-\(UUID().uuidString.lowercased())",
            kind: kind,
            bounds: CanvasWorkspaceRect(x: 180 + offset, y: 160 + offset, width: size.0, height: size.1),
            zIndex: (document.elements.map(\.zIndex).max() ?? 0) + 1,
            data: ["text": .string(text)]
        )
        await commit(
            [.init(kind: .createElement, element: element)],
            summary: "Added \(kind.rawValue)"
        )
        selectedElementID = element.id
    }

    func updateElement(_ element: CanvasWorkspaceElement, summary: String = "Updated element") async {
        await commit([.init(kind: .updateElement, element: element)], summary: summary)
    }

    func deleteSelectedElement() async {
        guard let selectedElementID else { return }
        await commit(
            [.init(kind: .deleteElement, targetId: selectedElementID)],
            summary: "Deleted element"
        )
        self.selectedElementID = nil
    }

    func savePencilDrawing(_ data: Data, previewPNG: Data?) async {
        guard var document else { return }
        let drawingID = "native-pencil-drawing"
        let value = CanvasJSONValue.string(data.base64EncodedString())
        let previewURL = previewPNG.map {
            CanvasJSONValue.string("data:image/png;base64,\($0.base64EncodedString())")
        }
        if let index = document.elements.firstIndex(where: { $0.id == drawingID }) {
            document.elements[index].data["pencilDrawing"] = value
            if let previewURL {
                document.elements[index].data["url"] = previewURL
            }
            await updateElement(document.elements[index], summary: "Updated Apple Pencil drawing")
        } else {
            var elementData: [String: CanvasJSONValue] = [
                "title": .string("Apple Pencil drawing"),
                "pencilDrawing": value,
            ]
            if let previewURL {
                elementData["url"] = previewURL
            }
            let element = CanvasWorkspaceElement(
                id: drawingID,
                kind: .image,
                bounds: CanvasWorkspaceRect(x: 0, y: 0, width: 3200, height: 2400),
                zIndex: -1,
                data: elementData
            )
            await commit([.init(kind: .createElement, element: element)], summary: "Added Apple Pencil drawing")
        }
    }

    var pencilDrawingData: Data? {
        guard let encoded = document?.elements.first(where: { $0.id == "native-pencil-drawing" })?
            .data["pencilDrawing"]?.stringValue else { return nil }
        return Data(base64Encoded: encoded)
    }

    func sendPrompt(
        _ prompt: String,
        regionAction: CanvasRegionAgentAction? = nil,
        regionPNG: Data? = nil
    ) async {
        let content = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let agentID = selectedAgentID,
              let workspaceID = selectedWorkspaceID,
              !isSendingPrompt else { return }
        isSendingPrompt = true
        isInspectorPresented = true
        editorStatus = "Starting agent session…"
        defer { isSendingPrompt = false }
        do {
            let sessionID: String
            if let activeSessionID {
                sessionID = activeSessionID
            } else {
                let session = try await apiClient.createAgentSession(
                    agentId: agentID,
                    title: title,
                    projectId: projectID,
                    workspaceId: workspaceID
                )
                activeSessionID = session.id
                sessionID = session.id
            }
            await startSessionStream(agentID: agentID, sessionID: sessionID)
            let submittedContent = regionAction?.agentPrompt(userPrompt: content) ?? content
            let attachments: [ChatAttachmentUpload] = regionPNG.map { data in
                [ChatAttachmentUpload(
                    name: "canvas-selection.png",
                    mimeType: "image/png",
                    sizeBytes: data.count,
                    contentBase64: data.base64EncodedString()
                )]
            } ?? []
            appendMessage(ChatMessage(
                id: "optimistic-user-\(UUID().uuidString)",
                role: .user,
                segments: [.init(kind: .text, text: content)]
            ))
            beginStreamingAssistantMessage(sessionID: sessionID)
            editorStatus = "Agent is working…"
            _ = try await apiClient.postSessionMessage(
                agentId: agentID,
                sessionId: sessionID,
                content: submittedContent,
                userId: "apple-client",
                attachments: attachments
            )
            await refreshSession()
            await loadNativeEditor()
        } catch {
            removeStreamingAssistantMessage()
            editorStatus = "Agent run failed"
            pageError = error.localizedDescription
        }
    }

    func refreshSession() async {
        guard let agentID = selectedAgentID, let sessionID = activeSessionID else { return }
        if let detail = try? await apiClient.fetchAgentSession(agentId: agentID, sessionId: sessionID) {
            reconcileMessages(with: detail.messages)
        }
    }

    private func startSessionStream(agentID: String, sessionID: String) async {
        guard streamedSessionID != sessionID || streamTask == nil else { return }
        stopSessionStream()

        let manager = SessionSocketManager(
            endpoint: apiClient.endpoint,
            agentId: agentID,
            sessionId: sessionID
        )
        socketManager = manager
        streamedSessionID = sessionID
        let stream = await manager.connect()
        streamTask = Task { @MainActor [weak self] in
            defer { Task { await manager.disconnect() } }
            for await update in stream {
                guard let self, self.activeSessionID == sessionID else { return }
                await self.handleStreamUpdate(update, agentID: agentID, sessionID: sessionID)
            }
        }
    }

    private func stopSessionStream() {
        streamTask?.cancel()
        streamTask = nil
        streamedSessionID = nil
        if let socketManager {
            Task { await socketManager.disconnect() }
        }
        socketManager = nil
    }

    private func handleStreamUpdate(
        _ update: ChatStreamUpdate,
        agentID: String,
        sessionID: String
    ) async {
        switch update.kind {
        case .sessionReady:
            if !isSendingPrompt {
                await refreshSession()
            }
        case .sessionDelta:
            if let delta = update.messageText, !delta.isEmpty {
                appendStreamingText(delta, sessionID: sessionID)
            }
        case .sessionEvent:
            if let message = update.message {
                upsertStreamMessage(message)
            }
            if let status = update.streamEvent?.runStatus {
                handleRunStatus(status, sessionID: sessionID)
            }
        case .sessionClosed, .sessionError:
            if let error = update.errorText, !error.isEmpty {
                pageError = error
            }
            removeStreamingAssistantMessage(ifEmptyOnly: true)
        case .heartbeat:
            break
        }
    }

    private func handleRunStatus(_ status: ChatRunStatusEvent, sessionID: String) {
        if status.stage.isWorking {
            if streamingMessageID == nil {
                beginStreamingAssistantMessage(sessionID: sessionID)
            }
            if status.stage == .responding,
               let text = status.expandedText,
               !text.isEmpty {
                replaceStreamingText(text, sessionID: sessionID)
            }
            editorStatus = status.label
            return
        }

        switch status.stage {
        case .done:
            editorStatus = "Agent run completed"
            Task {
                await refreshSession()
                await loadNativeEditor()
            }
        case .paused:
            editorStatus = status.label
        case .interrupted:
            editorStatus = "Agent run interrupted"
        case .thinking, .searching, .responding:
            break
        }
        removeStreamingAssistantMessage(ifEmptyOnly: true)
    }

    private func beginStreamingAssistantMessage(sessionID: String) {
        guard streamingMessageID == nil else { return }
        let id = "streaming-assistant-\(sessionID)"
        streamingMessageID = id
        appendMessage(ChatMessage(id: id, role: .assistant, segments: [.init(kind: .text, text: "")]))
    }

    private func appendStreamingText(_ text: String, sessionID: String) {
        if streamingMessageID == nil {
            beginStreamingAssistantMessage(sessionID: sessionID)
        }
        guard let streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == streamingMessageID }) else { return }
        let accumulated = messages[index].textContent + text
        messages[index].segments = [.init(kind: .text, text: accumulated)]
        chatScrollToken += 1
    }

    private func replaceStreamingText(_ text: String, sessionID: String) {
        if streamingMessageID == nil {
            beginStreamingAssistantMessage(sessionID: sessionID)
        }
        guard let streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == streamingMessageID }) else { return }
        messages[index].segments = [.init(kind: .text, text: text)]
        chatScrollToken += 1
    }

    private func upsertStreamMessage(_ message: ChatMessage) {
        if message.role == .assistant,
           !message.textContent.isEmpty,
           let streamingMessageID {
            messages.removeAll { $0.id == streamingMessageID }
            self.streamingMessageID = nil
        } else if message.role == .user {
            messages.removeAll { $0.id.hasPrefix("optimistic-user-") }
        }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        chatScrollToken += 1
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        chatScrollToken += 1
    }

    private func removeStreamingAssistantMessage(ifEmptyOnly: Bool = false) {
        guard let streamingMessageID,
              let message = messages.first(where: { $0.id == streamingMessageID }),
              !ifEmptyOnly || message.textContent.isEmpty else { return }
        messages.removeAll { $0.id == streamingMessageID }
        self.streamingMessageID = nil
        chatScrollToken += 1
    }

    private func reconcileMessages(with serverMessages: [ChatMessage]) {
        let streamingMessage = messages.first { $0.id == streamingMessageID }
        messages = serverMessages
        if let streamingMessage,
           !messages.contains(where: { $0.id == streamingMessage.id }) {
            messages.append(streamingMessage)
        }
        if let finalAssistant = serverMessages.last(where: {
            $0.role == .assistant && !$0.textContent.isEmpty
        }), let streamingMessageID,
           finalAssistant.createdAt >= (messages.first(where: { $0.id == streamingMessageID })?.createdAt ?? .distantFuture) {
            messages.removeAll { $0.id == streamingMessageID }
            self.streamingMessageID = nil
        }
        chatScrollToken += 1
    }

    private func commit(_ operations: [CanvasWorkspaceOperation], summary: String) async {
        guard var current = document, let workspaceID = selectedWorkspaceID else { return }
        let expected: [String: Int] = Dictionary(uniqueKeysWithValues: operations.compactMap { operation -> (String, Int)? in
            guard let id = operation.element?.id,
                  let existing = current.elements.first(where: { $0.id == id }) else { return nil }
            return (id, existing.revision)
        })
        let request = CanvasWorkspaceTransactionRequest(
            id: "tx-\(UUID().uuidString.lowercased())",
            baseRevision: current.revision,
            expectedElementRevisions: expected,
            operations: operations,
            summary: summary
        )
        apply(operations, to: &current)
        document = current
        do {
            let transaction = try await apiClient.applyCanvasWorkspaceTransaction(
                workspaceId: workspaceID,
                request: request
            )
            if var committedDocument = self.document {
                apply(transaction.operations, to: &committedDocument)
                committedDocument.revision = transaction.revision
                self.document = committedDocument
            }
            editorStatus = "Saved"
        } catch {
            pageError = error.localizedDescription
            await loadNativeEditor()
        }
    }

    private func apply(_ operations: [CanvasWorkspaceOperation], to document: inout CanvasWorkspaceDocument) {
        for operation in operations {
            switch operation.kind {
            case .createElement, .updateElement:
                guard let element = operation.element else { continue }
                document.elements.removeAll { $0.id == element.id }
                document.elements.append(element)
            case .deleteElement:
                document.elements.removeAll { $0.id == operation.targetId }
            }
        }
    }

    private func loadWidgetArtifacts() async {
        let ids = Set((document?.elements ?? []).compactMap { element in
            element.kind == .widget ? element.data["artifactId"]?.stringValue : nil
        })
        for id in ids where widgetHTML[id] == nil {
            if let artifact = try? await apiClient.fetchCanvasWidgetArtifact(id: id) {
                widgetHTML[id] = artifact.html
            }
        }
    }

    private static func workspaceURL(
        baseURL: URL,
        apiBaseURL: URL,
        workspaceID: String
    ) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/workspaces/\(workspaceID)"
        components?.queryItems = [
            URLQueryItem(name: "embed", value: "workspace"),
            URLQueryItem(name: "apiBase", value: apiBaseURL.absoluteString),
        ]
        return components?.url ?? baseURL
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

}

enum CanvasRegionAgentAction: String, CaseIterable, Identifiable {
    case explain
    case research
    case work

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .explain: "lightbulb"
        case .research: "magnifyingglass"
        case .work: "hammer"
        }
    }

    func agentPrompt(userPrompt: String) -> String {
        switch self {
        case .explain:
            "Explain the selected canvas region in the attached image. User request: \(userPrompt)"
        case .research:
            "Research the topic shown in the selected canvas region and answer with useful findings and sources. User request: \(userPrompt)"
        case .work:
            "Work collaboratively on the selected canvas region. Use the attached image as context and update or extend the relevant workspace content. User request: \(userPrompt)"
        }
    }
}
