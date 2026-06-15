import ArgumentParser
import Foundation
import Protocols

struct DeepResearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deepresearch",
        abstract: "Run configurable multi-round research through an agent session."
    )

    @Option(name: .long, help: "Research mode: compare, review, or explore.")
    var mode: String = DeepResearchCommandParser.defaultMode.rawValue

    @Option(name: .long, help: "Number of search+synthesis rounds, from 1 to 8.")
    var rounds: Int = DeepResearchCommandParser.defaultRounds

    @Option(name: .long, help: "Agent ID. If omitted, the workspace must have exactly one user agent.")
    var agent: String?

    @Option(name: .long, help: "Existing session ID to reuse.")
    var session: String?

    @Option(name: .long, help: "Project ID to attach to a newly created session.")
    var project: String?

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    @Argument(parsing: .remaining, help: "Research prompt.")
    var prompt: [String] = []

    mutating func run() async throws {
        let request: DeepResearchRequest
        do {
            request = try DeepResearchCommandParser.parseArguments(
                [
                    "--mode", mode,
                    "--rounds", "\(rounds)"
                ] + prompt
            )
        } catch let error as DeepResearchCommandParser.ValidationError {
            CLIStyle.error(error.description)
            throw ExitCode.validationFailure
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }

        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let agentID = try await resolveAgentID(agent, client: client)
            let sessionID = try await resolveSessionID(agentID: agentID, request: request, client: client)
            let payload = try JSONSerialization.data(withJSONObject: [
                "userId": "cli",
                "content": DeepResearchCommandParser.skillInvocationMessage(for: request),
                "mode": AgentChatMode.auto.rawValue
            ])
            let data = try await client.post(
                "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions/\(SloppyCLIClient.escape(sessionID))/messages",
                body: payload
            )
            CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
        } catch {
            CLIStyle.error(error.localizedDescription)
            throw ExitCode.failure
        }
    }

    private func resolveSessionID(
        agentID: String,
        request: DeepResearchRequest,
        client: SloppyCLIClient
    ) async throws -> String {
        if let session = session?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            return session
        }

        var body: [String: Any] = [
            "title": "Deep research: \(request.prompt.prefix(72))"
        ]
        if let project = project?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
            body["projectId"] = project
        }
        let data = try await client.post(
            "/v1/agents/\(SloppyCLIClient.escape(agentID))/sessions",
            body: JSONSerialization.data(withJSONObject: body)
        )
        let object = try Self.jsonObject(from: data)
        guard let id = object["id"] as? String, !id.isEmpty else {
            throw CLIError("Server did not return a session id.")
        }
        return id
    }

    private func resolveAgentID(_ requested: String?, client: SloppyCLIClient) async throws -> String {
        if let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines), !requested.isEmpty {
            return requested
        }

        let data = try await client.get("/v1/agents", query: ["system": "false"])
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CLIError("Server returned an invalid agents response.")
        }
        let ids = array.compactMap { ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard ids.count == 1, let id = ids.first else {
            throw CLIError("Use --agent when the workspace has zero or multiple user agents.")
        }
        return id
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError("Server returned invalid JSON.")
        }
        return object
    }
}
