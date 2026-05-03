import Foundation

struct SloppyTUIState: Codable, Sendable {
    struct Selection: Codable, Sendable {
        var agentId: String
        var sessionId: String?

        init(agentId: String = "", sessionId: String? = nil) {
            self.agentId = agentId
            self.sessionId = sessionId
        }
    }

    var selections: [String: Selection]
    var drafts: [String: String]

    init(selections: [String: Selection] = [:], drafts: [String: String] = [:]) {
        self.selections = selections
        self.drafts = drafts
    }
}

struct SloppyTUIStateStore {
    var workspaceRoot: URL
    var fileManager: FileManager = .default

    var stateURL: URL {
        workspaceRoot
            .appendingPathComponent("tui", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() -> SloppyTUIState {
        guard let data = try? Data(contentsOf: stateURL) else {
            return SloppyTUIState()
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode(SloppyTUIState.self, from: data)) ?? SloppyTUIState()
    }

    func save(_ state: SloppyTUIState) {
        do {
            try fileManager.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = try encoder.encode(state) + Data("\n".utf8)
            try payload.write(to: stateURL, options: .atomic)
        } catch {
            // Draft persistence should never take the TUI down.
        }
    }

    static func selectionKey(projectId: String) -> String {
        "project:\(projectId)"
    }

    static func draftKey(projectId: String, agentId: String, sessionId: String) -> String {
        "\(projectId):\(agentId):\(sessionId)"
    }
}
