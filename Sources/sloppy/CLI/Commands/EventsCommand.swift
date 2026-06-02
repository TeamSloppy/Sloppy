import ArgumentParser
import Foundation
import Protocols

enum EventWatchFormat: String, ExpressibleByArgument {
    case pretty
    case jsonl
}

struct EventsCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Observe live Sloppy events.",
        subcommands: [EventsWatchCommand.self]
    )
}

struct EventsWatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch a live agent session event stream."
    )

    @Option(name: .long, help: "Agent ID") var agent: String
    @Option(name: .long, help: "Agent session ID") var session: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long, help: "Output format: pretty or jsonl") var format: EventWatchFormat = .pretty
    @Flag(name: .long, help: "Include heartbeat events") var heartbeats: Bool = false
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let stream = client.streamAgentSessionEvents(agentID: agent, sessionID: session)
            for try await update in stream {
                if update.kind == .heartbeat && !heartbeats {
                    continue
                }
                guard let line = EventWatchOutputFormatter.line(for: update, format: format) else {
                    continue
                }
                print(line)
            }
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }
}

enum EventWatchOutputFormatter {
    static func line(for update: AgentSessionStreamUpdate, format: EventWatchFormat) -> String? {
        switch format {
        case .jsonl:
            return jsonLine(for: update)
        case .pretty:
            return prettyLine(for: update)
        }
    }

    private static func jsonLine(for update: AgentSessionStreamUpdate) -> String? {
        var object: [String: Any] = [
            "kind": update.kind.rawValue,
            "cursor": update.cursor,
            "created_at": timestamp(update.createdAt),
        ]
        if let message = update.message {
            object["message"] = message
        }
        if let summary = update.summary {
            object["agent_id"] = summary.agentId
            object["session_id"] = summary.id
            object["session_title"] = summary.title
        }
        if let event = update.event {
            object["event_id"] = event.id
            object["event_type"] = event.type.rawValue
            object["agent_id"] = event.agentId
            object["session_id"] = event.sessionId
            object["event_created_at"] = timestamp(event.createdAt)
            addEventDetails(event, to: &object)
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return line
    }

    private static func prettyLine(for update: AgentSessionStreamUpdate) -> String? {
        if update.kind == .sessionReady {
            return "#\(update.cursor) session_ready \(update.summary?.title ?? update.summary?.id ?? "")".trimmingCharacters(in: .whitespaces)
        }
        if update.kind == .sessionDelta, let message = update.message {
            return "#\(update.cursor) session_delta \(singleLine(message))"
        }
        if update.kind == .sessionClosed {
            return "#\(update.cursor) session_closed \(update.message ?? "")".trimmingCharacters(in: .whitespaces)
        }
        if update.kind == .heartbeat {
            return "#\(update.cursor) heartbeat"
        }
        guard let event = update.event else {
            return "#\(update.cursor) \(update.kind.rawValue)"
        }

        switch event.type {
        case .runStatus:
            guard let status = event.runStatus else { return nil }
            return "#\(update.cursor) run_status \(status.stage.rawValue) - \(status.label)"
        case .toolCall:
            guard let call = event.toolCall else { return nil }
            return "#\(update.cursor) tool_call \(call.tool)\(call.reason.map { " - \($0)" } ?? "")"
        case .toolResult:
            guard let result = event.toolResult else { return nil }
            let state = result.ok ? "ok" : "failed"
            let duration = result.durationMs.map { " \($0)ms" } ?? ""
            let error = result.error.map { " - \($0.message)" } ?? ""
            return "#\(update.cursor) tool_result \(result.tool) \(state)\(duration)\(error)"
        case .inputRequest:
            guard let request = event.inputRequest else { return nil }
            return "#\(update.cursor) input_request \(request.id) - \(request.title ?? request.questions.first?.question ?? "User input requested")"
        case .message:
            guard let message = event.message else { return nil }
            let text = message.segments.compactMap(\.text).joined(separator: " ")
            return "#\(update.cursor) message \(message.role.rawValue) - \(singleLine(text))"
        case .planArtifact:
            guard let artifact = event.planArtifact?.artifact else { return nil }
            return "#\(update.cursor) plan_artifact \(artifact.planName)"
        case .subSession:
            guard let subSession = event.subSession else { return nil }
            return "#\(update.cursor) sub_session \(subSession.childSessionId) - \(subSession.title)"
        case .inputResponse:
            guard let response = event.inputResponse else { return nil }
            return "#\(update.cursor) input_response \(response.requestId) - \(response.status.rawValue)"
        default:
            return "#\(update.cursor) \(event.type.rawValue)"
        }
    }

    private static func addEventDetails(_ event: AgentSessionEvent, to object: inout [String: Any]) {
        if let status = event.runStatus {
            object["stage"] = status.stage.rawValue
            object["label"] = status.label
            object["details"] = status.details
        }
        if let call = event.toolCall {
            object["tool"] = call.tool
            object["reason"] = call.reason
        }
        if let result = event.toolResult {
            object["tool"] = result.tool
            object["ok"] = result.ok
            object["duration_ms"] = result.durationMs
            object["error"] = result.error?.message
        }
        if let request = event.inputRequest {
            object["request_id"] = request.id
            object["mode"] = request.mode
            object["title"] = request.title
            object["question_count"] = request.questions.count
        }
        if let response = event.inputResponse {
            object["request_id"] = response.requestId
            object["status"] = response.status.rawValue
        }
        if let message = event.message {
            object["role"] = message.role.rawValue
            object["text"] = message.segments.compactMap(\.text).joined(separator: "\n")
        }
        object = object.compactMapValues { value in
            if let string = value as? String, string.isEmpty {
                return nil
            }
            return value
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func singleLine(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
