import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

struct StoredImageArtifact: Sendable {
    var id: String
    var fileURL: URL
    var mediaType: String
    var width: Int?
    var height: Int?
    var contentURL: String
    var manifestJSON: String
}

struct ImageArtifactManifest: Codable, Sendable, Equatable {
    var id: String
    var kind: String
    var fileName: String
    var mediaType: String
    var prompt: String
    var provider: String
    var model: String
    var modality: String
    var seed: Int?
    var width: Int?
    var height: Int?
    var createdAt: Date

    var apiMetadata: ArtifactImageMetadata {
        ArtifactImageMetadata(
            width: width,
            height: height,
            fileName: fileName,
            contentUrl: "/v1/artifacts/\(id)/file"
        )
    }
}

enum ImageArtifactService {
    enum ArtifactError: Error, Equatable {
        case invalidImage
        case responseTooLarge
        case invalidArtifact
    }

    static let maximumOutputBytes = 25 * 1024 * 1024
    static let manifestFileName = "manifest.json"

    static func create(
        remoteURL: URL,
        prompt: String,
        provider: String,
        model: String,
        modality: ImageGenerationModality,
        seed: Int?,
        width: Int?,
        height: Int?,
        workspaceRootURL: URL,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> StoredImageArtifact {
        guard isSafeRemoteImageURL(remoteURL) else {
            throw ArtifactError.invalidImage
        }
        var request = URLRequest(url: remoteURL)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw ArtifactError.invalidImage
        }
        guard !data.isEmpty else {
            throw ArtifactError.invalidImage
        }
        guard data.count <= maximumOutputBytes else {
            throw ArtifactError.responseTooLarge
        }

        let responseMediaType = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
        let mediaType = normalizedMediaType(responseMediaType, data: data)
        guard let mediaType else {
            throw ArtifactError.invalidImage
        }
        return try persist(
            data: data,
            mediaType: mediaType,
            prompt: prompt,
            provider: provider,
            model: model,
            modality: modality,
            seed: seed,
            width: width,
            height: height,
            workspaceRootURL: workspaceRootURL,
            fileManager: fileManager
        )
    }

    static func create(
        data: Data,
        mediaType declaredMediaType: String?,
        prompt: String,
        provider: String,
        model: String,
        modality: ImageGenerationModality,
        seed: Int?,
        width: Int?,
        height: Int?,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) throws -> StoredImageArtifact {
        guard !data.isEmpty else { throw ArtifactError.invalidImage }
        guard data.count <= maximumOutputBytes else { throw ArtifactError.responseTooLarge }
        guard let mediaType = normalizedMediaType(declaredMediaType?.lowercased(), data: data) else {
            throw ArtifactError.invalidImage
        }
        return try persist(
            data: data,
            mediaType: mediaType,
            prompt: prompt,
            provider: provider,
            model: model,
            modality: modality,
            seed: seed,
            width: width,
            height: height,
            workspaceRootURL: workspaceRootURL,
            fileManager: fileManager
        )
    }

    private static func persist(
        data: Data,
        mediaType: String,
        prompt: String,
        provider: String,
        model: String,
        modality: ImageGenerationModality,
        seed: Int?,
        width: Int?,
        height: Int?,
        workspaceRootURL: URL,
        fileManager: FileManager
    ) throws -> StoredImageArtifact {
        let fileExtension = fileExtension(for: mediaType)
        let id = UUID().uuidString.lowercased()
        let fileName = "image.\(fileExtension)"
        let directoryURL = bundleDirectoryURL(id: id, workspaceRootURL: workspaceRootURL)
        let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        let createdAt = Date()
        let manifest = ImageArtifactManifest(
            id: id,
            kind: "image",
            fileName: fileName,
            mediaType: mediaType,
            prompt: prompt,
            provider: provider,
            model: model,
            modality: modality.rawValue,
            seed: seed,
            width: width,
            height: height,
            createdAt: createdAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try manifestData.write(
                to: directoryURL.appendingPathComponent(manifestFileName, isDirectory: false),
                options: .atomic
            )
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }

        guard let manifestJSON = String(data: manifestData, encoding: .utf8) else {
            try? fileManager.removeItem(at: directoryURL)
            throw ArtifactError.invalidArtifact
        }
        return StoredImageArtifact(
            id: id,
            fileURL: fileURL,
            mediaType: mediaType,
            width: width,
            height: height,
            contentURL: "/v1/artifacts/\(id)/file",
            manifestJSON: manifestJSON
        )
    }

    static func file(
        record: PersistedArtifactRecord,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) -> (data: Data, mediaType: String)? {
        guard record.kind == "image",
              let manifest = manifest(from: record.content),
              manifest.id == record.id,
              normalizedArtifactID(record.id) != nil
        else {
            return nil
        }
        let fileURL = bundleDirectoryURL(id: record.id, workspaceRootURL: workspaceRootURL)
            .appendingPathComponent(manifest.fileName, isDirectory: false)
        guard fileURL.deletingLastPathComponent().standardizedFileURL
            == bundleDirectoryURL(id: record.id, workspaceRootURL: workspaceRootURL).standardizedFileURL,
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              data.count <= maximumOutputBytes
        else {
            return nil
        }
        return (data, manifest.mediaType)
    }

    static func metadata(from record: PersistedArtifactRecord) -> ArtifactImageMetadata? {
        guard record.kind == "image" else { return nil }
        return manifest(from: record.content)?.apiMetadata
    }

    static func deleteBundle(
        id: String,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) {
        guard normalizedArtifactID(id) != nil else { return }
        let directoryURL = bundleDirectoryURL(id: id, workspaceRootURL: workspaceRootURL)
        try? fileManager.removeItem(at: directoryURL)
    }

    static func bundlePath(id: String) -> String {
        ".sloppy/artifacts/images/\(id)/"
    }

    static func bundleDirectoryURL(id: String, workspaceRootURL: URL) -> URL {
        artifactsRootURL(workspaceRootURL: workspaceRootURL)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    private static func artifactsRootURL(workspaceRootURL: URL) -> URL {
        let normalized = workspaceRootURL.standardizedFileURL
        let sloppyRoot = normalized.lastPathComponent == CoreConfig.defaultWorkspaceName
            ? normalized
            : normalized.appendingPathComponent(CoreConfig.defaultWorkspaceName, isDirectory: true)
        return sloppyRoot.appendingPathComponent("artifacts", isDirectory: true)
    }

    private static func manifest(from content: String) -> ImageArtifactManifest? {
        guard let data = content.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ImageArtifactManifest.self, from: data)
    }

    private static func normalizedArtifactID(_ id: String) -> String? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    private static func normalizedMediaType(_ responseMediaType: String?, data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        let detected: String?
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            detected = "image/png"
        } else if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            detected = "image/jpeg"
        } else if bytes.count >= 12,
                  String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
                  String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            detected = "image/webp"
        } else {
            detected = nil
        }
        guard let detected else { return nil }
        if let responseMediaType,
           ["image/png", "image/jpeg", "image/webp"].contains(responseMediaType),
           responseMediaType != detected {
            return nil
        }
        return detected
    }

    private static func isSafeRemoteImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let rawHost = url.host?.lowercased(),
              !rawHost.isEmpty,
              rawHost != "localhost",
              !rawHost.hasSuffix(".localhost"),
              !rawHost.hasSuffix(".local")
        else {
            return false
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.contains(":"),
           (host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")) {
            return false
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            if parts[0] == 0 || parts[0] == 10 || parts[0] == 127 { return false }
            if parts[0] == 169 && parts[1] == 254 { return false }
            if parts[0] == 172 && (16...31).contains(parts[1]) { return false }
            if parts[0] == 192 && parts[1] == 168 { return false }
        }
        return true
    }

    private static func fileExtension(for mediaType: String) -> String {
        switch mediaType {
        case "image/jpeg": "jpg"
        case "image/webp": "webp"
        default: "png"
        }
    }
}
