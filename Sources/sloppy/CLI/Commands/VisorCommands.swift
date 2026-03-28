import ArgumentParser
import Foundation

struct VisorCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "visor",
        abstract: "Interact with Visor.",
        subcommands: [VisorChatCommand.self, VisorReadyCommand.self]
    )
}

struct VisorChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chat", abstract: "Send a question to Visor.")

    @Option(name: .long, help: "Question to ask") var question: String
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Option(name: .long) var format: String = "json"
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        let payload: [String: Any] = ["question": question]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.post("/v1/visor/chat", body: body)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let answer = json["answer"] as? String {
                print(answer)
            } else {
                CLIFormatters.output(data, format: CLIFormatters.resolveFormat(format))
            }
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}

struct VisorReadyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ready", abstract: "Check if Visor is ready.")

    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        let client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        do {
            let data = try await client.get("/v1/visor/ready")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ready = json["ready"] as? Bool {
                if ready {
                    CLIStyle.success("Visor is ready.")
                } else {
                    print(CLIStyle.yellow("Visor is not ready yet."))
                }
            } else {
                CLIFormatters.printJSON(data)
            }
        } catch {
            CLIStyle.error(error.localizedDescription); throw ExitCode.failure
        }
    }
}
