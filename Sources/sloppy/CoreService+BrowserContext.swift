import Foundation
import Protocols

extension CoreService {
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

        let message = Self.browserContextPrompt(
            page: request.page,
            selection: selectionText,
            browser: request.browser,
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
                mode: .ask
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

    static func browserContextPrompt(page: BrowserContextPage, selection: String, browser: BrowserContextBrowser? = nil, prompt: String) -> String {
        var lines: [String] = [
            "Source: Safari Extension",
            "URL: \(page.url)"
        ]
        if let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("Title: \(title)")
        }
        lines.append("")
        lines.append("Selected text:")
        lines.append(selection)
        if let snapshot = browser?.pageSnapshot,
           let snapshotText = browserContextSnapshotText(snapshot),
           !snapshotText.isEmpty {
            lines.append("")
            lines.append("Safari page snapshot:")
            lines.append(snapshotText)
        }
        lines.append("")
        lines.append("User prompt:")
        lines.append(prompt)
        return lines.joined(separator: "\n")
    }

    private static func browserContextSnapshotText(_ snapshot: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              var text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let limit = 24_000
        if text.count > limit {
            text = String(text.prefix(limit)) + "...[truncated]"
        }
        return text
    }
}
