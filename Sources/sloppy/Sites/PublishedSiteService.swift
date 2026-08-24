import Foundation
import Protocols

enum PublishedSiteService {
    enum SiteError: Error, Sendable, Equatable {
        case invalidSlug
        case invalidTitle
        case invalidEntryFile
        case invalidSource
        case forbiddenSourceEntry(String)
        case bundleTooLarge
        case tooManyFiles
        case slugConflict
        case notFound
        case forbidden
        case storageFailure
    }

    struct Content: Sendable {
        var data: Data
        var mediaType: String
    }

    static func normalizedSlug(_ raw: String) throws -> String {
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty,
              slug.count <= 80,
              slug.range(
                  of: "^[a-z0-9]+(?:-[a-z0-9]+)*$",
                  options: .regularExpression
              ) != nil
        else { throw SiteError.invalidSlug }
        return slug
    }

    static func normalizedTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw SiteError.invalidTitle }
        return title
    }

    static func normalizedEntryFile(_ raw: String) throws -> String {
        let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty,
              !entry.hasPrefix("/"),
              entry.split(separator: "/").allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw SiteError.invalidEntryFile }
        return entry
    }

    static func bundlePath(siteID: String) -> String {
        "sites/\(siteID)/current"
    }

    static func installBundle(
        sourceURL: URL,
        siteID: String,
        entryFile: String,
        workspaceRootURL: URL,
        limits: CoreConfig.Sites = .init(),
        fileManager: FileManager = .default
    ) throws {
        let source = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw SiteError.invalidSource }

        let sitesRoot = sitesRootURL(workspaceRootURL: workspaceRootURL)
        guard source.path != sitesRoot.path, !source.path.hasPrefix(sitesRoot.path + "/") else {
            throw SiteError.invalidSource
        }

        let siteRoot = sitesRoot.appendingPathComponent(siteID, isDirectory: true)
        let staging = siteRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let current = siteRoot.appendingPathComponent("current", isDirectory: true)
        let backup = siteRoot.appendingPathComponent(".previous-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try copyValidatedBundle(
                from: source,
                to: staging,
                limits: limits,
                fileManager: fileManager
            )
            let installedEntry = staging.appendingPathComponent(entryFile).standardizedFileURL
            guard installedEntry.path.hasPrefix(staging.path + "/"),
                  fileManager.fileExists(atPath: installedEntry.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { throw SiteError.invalidEntryFile }

            let hadCurrent = fileManager.fileExists(atPath: current.path)
            if hadCurrent {
                try fileManager.moveItem(at: current, to: backup)
            }
            do {
                try fileManager.moveItem(at: staging, to: current)
                if hadCurrent {
                    try? fileManager.removeItem(at: backup)
                }
            } catch {
                if hadCurrent, fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: current)
                }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    static func removeBundle(
        siteID: String,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let siteRoot = sitesRootURL(workspaceRootURL: workspaceRootURL)
            .appendingPathComponent(siteID, isDirectory: true)
            .standardizedFileURL
        if fileManager.fileExists(atPath: siteRoot.path) {
            try fileManager.removeItem(at: siteRoot)
        }
    }

    static func content(
        site: PersistedPublishedSiteRecord,
        assetPath: String,
        workspaceRootURL: URL,
        fileManager: FileManager = .default
    ) -> Content? {
        let root = workspaceRootURL
            .appendingPathComponent(site.bundlePath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else { return nil }

        let normalized = assetPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }

        let requested = components.reduce(root) {
            $0.appendingPathComponent($1, isDirectory: false)
        }.resolvingSymlinksInPath().standardizedFileURL
        guard requested.path == root.path || requested.path.hasPrefix(root.path + "/") else { return nil }

        var isDirectory: ObjCBool = false
        var candidate = requested
        if components.isEmpty {
            candidate = root.appendingPathComponent(site.entryFile)
        } else if fileManager.fileExists(atPath: requested.path, isDirectory: &isDirectory), isDirectory.boolValue {
            candidate = requested.appendingPathComponent(site.entryFile)
        }

        if !fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) || isDirectory.boolValue {
            let last = components.last ?? ""
            guard !last.contains(".") else { return nil }
            candidate = root.appendingPathComponent(site.entryFile)
        }
        guard candidate.path.hasPrefix(root.path + "/"),
              let data = try? Data(contentsOf: candidate)
        else { return nil }
        return Content(data: data, mediaType: mediaType(for: candidate.pathExtension))
    }

    private static func copyValidatedBundle(
        from source: URL,
        to destination: URL,
        limits: CoreConfig.Sites,
        fileManager: FileManager
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else { throw SiteError.invalidSource }

        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            let relative = String(item.standardizedFileURL.path.dropFirst(source.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = relative.split(separator: "/").map(String.init)
            guard !components.contains(where: isForbiddenComponent) else {
                throw SiteError.forbiddenSourceEntry(relative)
            }
            guard values.isSymbolicLink != true else {
                throw SiteError.forbiddenSourceEntry(relative)
            }

            let target = destination.appendingPathComponent(relative, isDirectory: values.isDirectory == true)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)
                guard fileCount <= limits.maximumFileCount else { throw SiteError.tooManyFiles }
                guard totalBytes <= limits.maximumBundleBytes else { throw SiteError.bundleTooLarge }
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    private static func isForbiddenComponent(_ component: String) -> Bool {
        let lowercased = component.lowercased()
        return lowercased == ".git"
            || lowercased == ".sloppy"
            || lowercased == "node_modules"
            || lowercased == ".env"
            || lowercased.hasPrefix(".env.")
    }

    private static func sitesRootURL(workspaceRootURL: URL) -> URL {
        workspaceRootURL
            .standardizedFileURL
            .appendingPathComponent("sites", isDirectory: true)
            .standardizedFileURL
    }

    private static func mediaType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "json", "map": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
