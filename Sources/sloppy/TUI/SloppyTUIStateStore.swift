import Foundation

enum SloppyTUIScrollbackMode: String, Codable, Sendable, CaseIterable {
    case auto
    case viewport
    case limited
    case full
}

enum SloppyTUITimelineScrollBehavior: Equatable {
    case native(limit: Int?)
    case viewport(limit: Int?)

    var usesViewport: Bool {
        if case .viewport = self {
            return true
        }
        return false
    }
}

enum SloppyTUIScrollbackPolicy {
    static let defaultLineLimit = 2_000

    static func normalizedLineLimit(_ value: Int) -> Int {
        max(1, value)
    }

    static func behavior(
        mode: SloppyTUIScrollbackMode,
        lineLimit: Int,
        totalLineCount: Int
    ) -> SloppyTUITimelineScrollBehavior {
        let limit = normalizedLineLimit(lineLimit)
        switch mode {
        case .auto:
            return totalLineCount > limit ? .viewport(limit: nil) : .native(limit: limit)
        case .viewport, .full:
            return .viewport(limit: nil)
        case .limited:
            return .viewport(limit: limit)
        }
    }

    static func nativeLineRange(
        behavior: SloppyTUITimelineScrollBehavior,
        totalLineCount: Int
    ) -> Range<Int>? {
        let total = max(0, totalLineCount)
        switch behavior {
        case .native(let limit):
            let start = limit.map { max(0, total - normalizedLineLimit($0)) } ?? 0
            return start..<total
        case .viewport:
            return nil
        }
    }

    static func viewportLineRange(
        behavior: SloppyTUITimelineScrollBehavior,
        totalLineCount: Int
    ) -> Range<Int> {
        let total = max(0, totalLineCount)
        switch behavior {
        case .native:
            return 0..<total
        case .viewport(let limit):
            let start = limit.map { max(0, total - normalizedLineLimit($0)) } ?? 0
            return start..<total
        }
    }
}

struct SloppyTUIState: Codable, Sendable {
    struct Selection: Codable, Sendable {
        var agentId: String
        var sessionId: String?

        init(agentId: String = "", sessionId: String? = nil) {
            self.agentId = agentId
            self.sessionId = sessionId
        }
    }

    struct TrackedSession: Codable, Sendable, Equatable {
        var agentId: String
        var sessionId: String
        var pinned: Bool
        var background: Bool
        var worktreePath: String?
        var worktreeBranch: String?
        var createdAt: Date
        var lastOpenedAt: Date?

        init(
            agentId: String,
            sessionId: String,
            pinned: Bool = false,
            background: Bool = false,
            worktreePath: String? = nil,
            worktreeBranch: String? = nil,
            createdAt: Date = Date(),
            lastOpenedAt: Date? = nil
        ) {
            self.agentId = agentId
            self.sessionId = sessionId
            self.pinned = pinned
            self.background = background
            self.worktreePath = worktreePath
            self.worktreeBranch = worktreeBranch
            self.createdAt = createdAt
            self.lastOpenedAt = lastOpenedAt
        }
    }

    var selections: [String: Selection]
    var drafts: [String: String]
    var sessionDirectories: [String: [String]]
    var trackedSessions: [String: [TrackedSession]]
    var petEnabled: Bool
    var welcomeTipCursor: Int
    var scrollbackMode: SloppyTUIScrollbackMode
    var scrollbackLineLimit: Int
    var themeID: String

    enum CodingKeys: String, CodingKey {
        case selections
        case drafts
        case sessionDirectories
        case trackedSessions
        case petEnabled
        case welcomeTipCursor
        case scrollbackMode
        case scrollbackLineLimit
        case themeID
    }

    init(
        selections: [String: Selection] = [:],
        drafts: [String: String] = [:],
        sessionDirectories: [String: [String]] = [:],
        trackedSessions: [String: [TrackedSession]] = [:],
        petEnabled: Bool = true,
        welcomeTipCursor: Int = 0,
        scrollbackMode: SloppyTUIScrollbackMode = .auto,
        scrollbackLineLimit: Int = SloppyTUIScrollbackPolicy.defaultLineLimit,
        themeID: String = SloppyTUIResolvedTheme.defaultID
    ) {
        self.selections = selections
        self.drafts = drafts
        self.sessionDirectories = sessionDirectories
        self.trackedSessions = trackedSessions
        self.petEnabled = petEnabled
        self.welcomeTipCursor = welcomeTipCursor
        self.scrollbackMode = scrollbackMode
        self.scrollbackLineLimit = SloppyTUIScrollbackPolicy.normalizedLineLimit(scrollbackLineLimit)
        self.themeID = Self.normalizedThemeID(themeID)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selections = try container.decodeIfPresent([String: Selection].self, forKey: .selections) ?? [:]
        drafts = try container.decodeIfPresent([String: String].self, forKey: .drafts) ?? [:]
        sessionDirectories = try container.decodeIfPresent([String: [String]].self, forKey: .sessionDirectories) ?? [:]
        trackedSessions = try container.decodeIfPresent([String: [TrackedSession]].self, forKey: .trackedSessions) ?? [:]
        petEnabled = try container.decodeIfPresent(Bool.self, forKey: .petEnabled) ?? true
        welcomeTipCursor = try container.decodeIfPresent(Int.self, forKey: .welcomeTipCursor) ?? 0
        scrollbackMode = (try? container.decodeIfPresent(SloppyTUIScrollbackMode.self, forKey: .scrollbackMode)) ?? .auto
        scrollbackLineLimit = SloppyTUIScrollbackPolicy.normalizedLineLimit(
            (try? container.decodeIfPresent(Int.self, forKey: .scrollbackLineLimit)) ?? SloppyTUIScrollbackPolicy.defaultLineLimit
        )
        themeID = Self.normalizedThemeID(
            (try? container.decodeIfPresent(String.self, forKey: .themeID)) ?? SloppyTUIResolvedTheme.defaultID
        )
    }

    private static func normalizedThemeID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SloppyTUIResolvedTheme.defaultID : trimmed
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

    static func trackedSessionsKey(projectId: String) -> String {
        "project:\(projectId)"
    }

    static func draftKey(projectId: String, agentId: String, sessionId: String) -> String {
        "\(projectId):\(agentId):\(sessionId)"
    }

    static func sessionDirectoryKey(projectId: String, agentId: String, sessionId: String) -> String {
        "\(projectId):\(agentId):\(sessionId)"
    }
}
