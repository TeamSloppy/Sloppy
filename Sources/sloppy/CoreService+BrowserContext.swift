import Foundation
import Protocols

extension CoreService {
    private static let widgetEditorAllowedTools: Set<String> = [
        "artifacts.widget.generate",
        "planning.select_route",
        "safari.dom_snapshot",
        "safari.tabs",
        "session.complete",
        "system.list_tools"
    ]

    public enum BrowserContextError: Error {
        case invalidPayload
        case invalidAgentID
        case invalidSessionID
        case agentNotFound
    }

    public func postBrowserContextMessage(_ request: BrowserContextMessageRequest) async throws -> BrowserContextMessageResponse {
        let agentID = request.target.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentID.isEmpty else {
            throw BrowserContextError.invalidAgentID
        }

        let selection = request.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageURL = request.page.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !pageURL.isEmpty else {
            throw BrowserContextError.invalidPayload
        }
        let selectionText = selection.isEmpty ? "No selected text." : selection

        let sessionID: String
        if let existingSessionID = request.target.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingSessionID.isEmpty {
            _ = try getAgentSession(agentID: agentID, sessionID: existingSessionID)
            sessionID = existingSessionID
        } else {
            let hostTitle = URL(string: pageURL)?.host ?? "Safari"
            let created = try await createAgentSession(
                agentID: agentID,
                request: AgentSessionCreateRequest(title: "Safari: \(hostTitle)")
            )
            sessionID = created.id
        }

        if Self.isWidgetEditorSession(request.widgetSession) {
            configureWidgetEditorToolAllowList(sessionID: sessionID)
        }

        let message = Self.browserContextPrompt(
            page: request.page,
            selection: selectionText,
            browser: request.browser,
            context: request.context,
            prompt: prompt
        )
        let response = try await postAgentSessionMessage(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionPostMessageRequest(
                userId: request.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "safari_extension" : request.userId,
                content: message,
                attachments: request.attachments,
                spawnSubSession: false,
                mode: .auto
            )
        )
        let assistantText = latestAssistantText(from: response.appendedEvents)
        let messageID = response.appendedEvents.last(where: { $0.message?.role == .assistant })?.message?.id
            ?? response.appendedEvents.last?.id

        return BrowserContextMessageResponse(
            sessionId: sessionID,
            messageId: messageID,
            status: "completed",
            text: assistantText
        )
    }

    private static func isWidgetEditorSession(_ widgetSession: BrowserWidgetSession?) -> Bool {
        let normalizedMode = widgetSession?.mode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedMode == "widget_editor"
    }

    func configureWidgetEditorToolAllowList(sessionID: String) {
        sessionSubagentToolAllowList[sessionID] = Self.widgetEditorAllowedTools
    }

    static func browserContextPrompt(
        page: BrowserContextPage,
        selection: String,
        browser: BrowserContextBrowser? = nil,
        context: BrowserContextMessageContext? = nil,
        prompt: String
    ) -> String {
        var lines: [String] = [
            "Source: Safari Extension",
            "URL: \(page.url)"
        ]
        if let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("Title: \(title)")
        }
        if let projectReference = context?.projectReference?.trimmingCharacters(in: .whitespacesAndNewlines), !projectReference.isEmpty {
            lines.append("Requested project reference: @\(projectReference)")
        }
        if let taskReference = context?.taskReference?.trimmingCharacters(in: .whitespacesAndNewlines), !taskReference.isEmpty {
            lines.append("Requested task reference: #\(taskReference)")
        }
        lines.append("")
        lines.append("Selected text:")
        lines.append(selection)
        lines.append("")
        lines.append("Safari tools:")
        lines.append("Use `safari.dom_snapshot` only when live page details are needed. Use `safari.click`, `safari.type`, and other `safari.*` tools for the user's current Safari tab; do not use `browser.*` for this Safari page.")
        if let projectReference = context?.projectReference?.trimmingCharacters(in: .whitespacesAndNewlines), !projectReference.isEmpty {
            lines.append("Use `project.list` to resolve the project named `\(projectReference)` before answering, and use that project context in your work.")
        }
        if let taskReference = context?.taskReference?.trimmingCharacters(in: .whitespacesAndNewlines), !taskReference.isEmpty {
            lines.append("Use `project.task_get` to resolve the task reference `\(taskReference)` before answering. If needed, try it as both `reference` and `taskId`.")
        }
        lines.append("")
        lines.append("User prompt:")
        lines.append(prompt)
        return lines.joined(separator: "\n")
    }
}
