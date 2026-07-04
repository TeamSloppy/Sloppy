import Foundation
import Protocols

struct BoardArtifactService {
    struct Manifest: Codable {
        let id: String
        let kind: String
        let version: Int
        let entry: String
        let bundlePath: String
        let updatedAt: Date
    }

    enum BoardError: Error, Equatable {
        case invalidBoardId
        case invalidBoard
        case invalidAsset
    }

    static let boardFileName = "board.json"
    static let manifestFileName = "manifest.json"

    static func bundlePath(id: String) -> String {
        ".sloppy/artifacts/boards/\(id)/"
    }

    static func bundleDirectoryURL(id: String, currentRootURL: URL) -> URL {
        currentRootURL
            .appendingPathComponent(CoreConfig.defaultWorkspaceName, isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("boards", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func loadBoard(
        id: String,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> BoardArtifactRecord? {
        let boardId = try normalizedBoardId(id)
        let boardURL = bundleDirectoryURL(id: boardId, currentRootURL: currentRootURL)
            .appendingPathComponent(boardFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: boardURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: boardURL)
        return try JSONDecoder().decode(BoardArtifactRecord.self, from: data)
    }

    static func saveBoard(
        _ board: BoardArtifactRecord,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> BoardArtifactRecord {
        let boardId = try normalizedBoardId(board.id)
        let normalized = try normalizedBoard(board, id: boardId)
        let directoryURL = bundleDirectoryURL(id: boardId, currentRootURL: currentRootURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(
            to: directoryURL.appendingPathComponent(boardFileName, isDirectory: false),
            options: .atomic
        )
        let manifest = Manifest(
            id: boardId,
            kind: "board",
            version: normalized.version,
            entry: boardFileName,
            bundlePath: bundlePath(id: boardId),
            updatedAt: Date()
        )
        try encoder.encode(manifest).write(
            to: directoryURL.appendingPathComponent(manifestFileName, isDirectory: false),
            options: .atomic
        )
        return normalized
    }

    static func writeAsset(
        boardId: String,
        request: BoardAssetUploadRequest,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> BoardAssetUploadResponse {
        let id = try normalizedBoardId(boardId)
        let mediaType = request.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mediaType.hasPrefix("image/"),
              let data = Data(base64Encoded: request.dataBase64),
              !data.isEmpty
        else {
            throw BoardError.invalidAsset
        }

        let ext = assetExtension(filename: request.filename, mediaType: mediaType)
        let assetId = UUID().uuidString
        let relativePath = "\(bundlePath(id: id))assets/\(assetId).\(ext)"
        let directoryURL = bundleDirectoryURL(id: id, currentRootURL: currentRootURL)
            .appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(
            to: directoryURL.appendingPathComponent("\(assetId).\(ext)", isDirectory: false),
            options: .atomic
        )
        return BoardAssetUploadResponse(path: relativePath, mediaType: mediaType, sizeBytes: data.count)
    }

    private static func normalizedBoardId(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw BoardError.invalidBoardId
        }
        return trimmed
    }

    private static func normalizedBoard(_ board: BoardArtifactRecord, id: String) throws -> BoardArtifactRecord {
        guard board.version == 1 else {
            throw BoardError.invalidBoard
        }
        let viewport = BoardCanvasViewport(
            x: finite(board.viewport.x, fallback: 0),
            y: finite(board.viewport.y, fallback: 0),
            scale: min(3, max(0.2, finite(board.viewport.scale, fallback: 1)))
        )
        let items = board.items.compactMap(normalizedItem)
        let groups = board.groups.compactMap(normalizedGroup)
        return BoardArtifactRecord(id: id, version: 1, viewport: viewport, items: items, groups: groups)
    }

    private static func normalizedItem(_ item: BoardCanvasItem) -> BoardCanvasItem? {
        let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = item.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, ["widget", "shortcut", "text", "image"].contains(type) else {
            return nil
        }
        return BoardCanvasItem(
            id: id,
            type: type,
            x: finite(item.x, fallback: 0),
            y: finite(item.y, fallback: 0),
            width: max(40, finite(item.width, fallback: 220)),
            height: max(40, finite(item.height, fallback: 140)),
            title: String(item.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            zIndex: item.zIndex,
            groupId: trimmedOptional(item.groupId),
            artifactId: trimmedOptional(item.artifactId),
            url: trimmedOptional(item.url),
            text: item.text,
            assetPath: trimmedOptional(item.assetPath),
            mediaType: trimmedOptional(item.mediaType)
        )
    }

    private static func normalizedGroup(_ group: BoardCanvasGroup) -> BoardCanvasGroup? {
        let id = group.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return nil
        }
        return BoardCanvasGroup(
            id: id,
            title: String(group.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            x: finite(group.x, fallback: 0),
            y: finite(group.y, fallback: 0),
            width: max(80, finite(group.width, fallback: 360)),
            height: max(80, finite(group.height, fallback: 220)),
            collapsed: group.collapsed,
            color: normalizedColor(group.color)
        )
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedColor(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pattern = #"^#[0-9A-Fa-f]{6}$"#
        return trimmed.range(of: pattern, options: .regularExpression) == nil ? nil : trimmed.lowercased()
    }

    private static func assetExtension(filename: String, mediaType: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "svg"].contains(ext) {
            return ext == "jpeg" ? "jpg" : ext
        }
        switch mediaType {
        case "image/jpeg":
            return "jpg"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/svg+xml":
            return "svg"
        default:
            return "png"
        }
    }
}
