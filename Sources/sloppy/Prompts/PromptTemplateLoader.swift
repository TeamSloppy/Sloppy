import Foundation

struct PromptTemplateLoader {
    enum LoaderError: Error, Equatable {
        case templateNotFound(String)
        case unreadableTemplate(String)
    }

    typealias Resolver = @Sendable (_ relativePath: String) throws -> String

    private let resolver: Resolver

    init(
        basePath: String = "Prompts/en",
        fileManager: FileManager = .default,
        executablePath: String? = CommandLine.arguments.first,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) {
        let searchRoots = Self.searchRoots(
            fileManager: fileManager,
            basePath: basePath,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath,
            sourceFilePath: sourceFilePath
        )

        self.resolver = { relativePath in
            guard let url = searchRoots
                .map({ $0.appendingPathComponent(relativePath) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) })
            else {
                throw LoaderError.templateNotFound(relativePath)
            }

            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw LoaderError.unreadableTemplate(relativePath)
            }
        }
    }

    init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    func loadTemplate(for processKind: PromptProcessKind) throws -> String {
        try resolver("\(processKind.templateName).md")
    }

    func loadPartial(named name: String) throws -> String {
        do {
            return try resolver("partials/\(name).md")
        } catch LoaderError.templateNotFound {
            // SwiftPM bundles can flatten processed resources in release/debug
            // artifacts, so keep a compatibility fallback to the root filename.
            return try resolver("\(name).md")
        }
    }
}

private extension PromptTemplateLoader {
    static func searchRoots(
        fileManager: FileManager,
        basePath: String,
        executablePath: String?,
        currentDirectoryPath: String,
        sourceFilePath: String
    ) -> [URL] {
        var roots: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard seenPaths.insert(normalized.path).inserted else { return }
            roots.append(normalized)
        }

        for directoryURL in executableDirectories(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath
        ) {
            append(directoryURL.appendingPathComponent(basePath))
            append(
                directoryURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("share/sloppy")
                    .appendingPathComponent(basePath)
            )
            append(
                directoryURL
                    .appendingPathComponent("Sloppy_sloppy.bundle")
                    .appendingPathComponent(basePath)
            )
            append(
                directoryURL
                    .appendingPathComponent("Sloppy_sloppy.resources")
                    .appendingPathComponent(basePath)
            )
        }

        append(
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Sources/sloppy/Resources")
                .appendingPathComponent(basePath)
        )

        append(
            URL(fileURLWithPath: sourceFilePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(basePath)
        )

        return roots
    }

    static func executableDirectories(
        fileManager: FileManager,
        executablePath: String?,
        currentDirectoryPath: String
    ) -> [URL] {
        guard let executablePath, !executablePath.isEmpty else {
            return []
        }

        let currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let rawExecutableURL: URL
        if executablePath.hasPrefix("/") {
            rawExecutableURL = URL(fileURLWithPath: executablePath)
        } else {
            rawExecutableURL = URL(fileURLWithPath: executablePath, relativeTo: currentDirectoryURL)
        }

        var directories: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let normalized = url.standardizedFileURL.deletingLastPathComponent()
            guard seenPaths.insert(normalized.path).inserted else { return }
            directories.append(normalized)
        }

        append(rawExecutableURL)
        append(rawExecutableURL.resolvingSymlinksInPath())

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: rawExecutableURL.path) {
            let destinationURL: URL
            if destination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: destination)
            } else {
                destinationURL = rawExecutableURL.deletingLastPathComponent().appendingPathComponent(destination)
            }
            append(destinationURL)
        }

        return directories
    }
}
