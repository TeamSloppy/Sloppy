import Foundation

public struct ProjectFileEntry: Codable, Sendable, Equatable {
    public enum EntryType: String, Codable, Sendable {
        case file
        case directory
    }

    public var name: String
    public var type: EntryType
    public var size: Int?

    public init(name: String, type: EntryType, size: Int? = nil) {
        self.name = name
        self.type = type
        self.size = size
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
