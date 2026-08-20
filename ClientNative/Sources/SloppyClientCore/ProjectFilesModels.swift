import Foundation

public struct ProjectFileEntry: Codable, Sendable, Equatable {
    public enum EntryType: String, Codable, Sendable {
        case file
        case directory
    }

    public var name: String
    public var path: String?
    public var type: EntryType
    public var size: Int?

    public init(name: String, path: String? = nil, type: EntryType, size: Int? = nil) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
    }
}

public struct ProjectFileSearchEntry: Codable, Sendable, Equatable {
    public var path: String
    public var type: ProjectFileEntry.EntryType

    public init(path: String, type: ProjectFileEntry.EntryType) {
        self.path = path
        self.type = type
    }
}

public struct ProjectFileContentResponse: Codable, Sendable, Equatable {
    public var path: String
    public var content: String
    public var sizeBytes: Int

    public init(path: String, content: String, sizeBytes: Int) {
        self.path = path
        self.content = content
        self.sizeBytes = sizeBytes
    }
}

public struct ProjectSourceControlFileChange: Sendable, Equatable, Identifiable {
    public var path: String
    public var linesAdded: Int
    public var linesDeleted: Int

    public var id: String { path }

    public init(path: String, linesAdded: Int = 0, linesDeleted: Int = 0) {
        self.path = path
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
    }
}

public struct ProjectWorkingTreeSourceControlResponse: Codable, Sendable, Equatable {
    public var providerId: String
    public var isRepository: Bool
    public var branch: String?
    public var linesAdded: Int
    public var linesDeleted: Int
    public var diff: String
    public var diffTruncated: Bool
    public var message: String?

    public init(
        providerId: String,
        isRepository: Bool,
        branch: String? = nil,
        linesAdded: Int = 0,
        linesDeleted: Int = 0,
        diff: String = "",
        diffTruncated: Bool = false,
        message: String? = nil
    ) {
        self.providerId = providerId
        self.isRepository = isRepository
        self.branch = branch
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.diff = diff
        self.diffTruncated = diffTruncated
        self.message = message
    }

    public var fileChanges: [ProjectSourceControlFileChange] {
        ProjectSourceControlDiffParser.fileChanges(in: diff)
    }

    public var hasChanges: Bool {
        isRepository && (!fileChanges.isEmpty || linesAdded > 0 || linesDeleted > 0)
    }
}

public enum ProjectSourceControlDiffParser {
    public static func fileChanges(in diff: String) -> [ProjectSourceControlFileChange] {
        var changes: [ProjectSourceControlFileChange] = []
        var currentPath: String?
        var linesAdded = 0
        var linesDeleted = 0
        var isInsideHunk = false

        func appendCurrentChange() {
            guard let currentPath else { return }
            changes.append(
                ProjectSourceControlFileChange(
                    path: currentPath,
                    linesAdded: linesAdded,
                    linesDeleted: linesDeleted
                )
            )
        }

        for line in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("diff --git ") {
                appendCurrentChange()
                currentPath = pathFromDiffHeader(line)
                linesAdded = 0
                linesDeleted = 0
                isInsideHunk = false
                continue
            }

            if line.hasPrefix("+++ "), let path = normalizedPatchPath(String(line.dropFirst(4))) {
                currentPath = path
                continue
            }

            if line.hasPrefix("@@") {
                isInsideHunk = true
                continue
            }

            guard isInsideHunk else { continue }
            if line.hasPrefix("+") {
                linesAdded += 1
            } else if line.hasPrefix("-") {
                linesDeleted += 1
            }
        }

        appendCurrentChange()
        return changes
    }

    private static func pathFromDiffHeader(_ line: String) -> String? {
        guard let markerRange = line.range(of: " b/", options: .backwards) else {
            return nil
        }
        return normalizedPatchPath(String(line[markerRange.upperBound...]), removesBPrefix: false)
    }

    private static func normalizedPatchPath(
        _ rawValue: String,
        removesBPrefix: Bool = true
    ) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != "/dev/null", !value.isEmpty else { return nil }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }
        if removesBPrefix, value.hasPrefix("b/") {
            value.removeFirst(2)
        }
        return value.replacingOccurrences(of: "\\\"", with: "\"")
    }
}

public struct WorkspacePanelDragPayload: Codable, Equatable, Sendable {
    public var projectId: String
    public var path: String
    public var type: String

    public init(projectId: String, path: String, type: String) {
        self.projectId = projectId
        self.path = path
        self.type = type
    }

    public var encodedValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return path
        }
        return text
    }

    public static func decode(from value: String) -> WorkspacePanelDragPayload? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspacePanelDragPayload.self, from: data)
    }
}
