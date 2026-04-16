import Foundation

enum SloppyVersion {
    static let devPlaceholder = "__SLOPPY_APP_VERSION__"
    private static let versionFileName = "sloppy-version.json"
    private static let bundledResourceDirectoryNames = [
        "Sloppy_sloppy.bundle",
        "Sloppy_sloppy.resources"
    ]

    static let releaseVersion: String? = {
        loadReleaseVersion()
    }()

    static let current: String = {
        let resolver = BuildMetadataResolver()
        return resolver.resolve().displayVersion
    }()

    static let isReleaseBuild: Bool = releaseVersion != nil

    static func loadReleaseVersion(
        fileManager: FileManager = .default,
        executablePath: String? = CommandLine.arguments.first,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) -> String? {
        for url in versionFileURLs(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath,
            sourceFilePath: sourceFilePath
        ) {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            if let version = releaseVersion(at: url) {
                return version
            }
        }
        return nil
    }

    static func releaseVersion(at url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let core = json["sloppy-core"] as? [String: Any],
            let version = core["version"] as? String
        else {
            return nil
        }

        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != devPlaceholder else {
            return nil
        }
        return trimmed
    }

    static func versionFileURLs(
        fileManager: FileManager = .default,
        executablePath: String? = CommandLine.arguments.first,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) -> [URL] {
        var candidates: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let normalized = url.standardizedFileURL.path
            guard seenPaths.insert(normalized).inserted else { return }
            candidates.append(url.standardizedFileURL)
        }

        for directoryURL in executableDirectories(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath
        ) {
            append(directoryURL.appendingPathComponent(versionFileName))

            for resourceDirectoryName in bundledResourceDirectoryNames {
                append(
                    directoryURL
                        .appendingPathComponent(resourceDirectoryName)
                        .appendingPathComponent(versionFileName)
                )
            }

            append(
                directoryURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("share/sloppy")
                    .appendingPathComponent(versionFileName)
            )
        }

        append(
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Sources/sloppy/Resources")
                .appendingPathComponent(versionFileName)
        )

        append(
            URL(fileURLWithPath: sourceFilePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(versionFileName)
        )

        return candidates
    }

    private static func executableDirectories(
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
            let directoryURL = url.standardizedFileURL.deletingLastPathComponent()
            guard seenPaths.insert(directoryURL.path).inserted else { return }
            directories.append(directoryURL)
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

    /// Returns true if `candidate` is a newer semver than `current`.
    /// Compares dot-separated integer segments; missing segments treated as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { v in
            v.split(separator: ".").compactMap { Int($0) }
        }
        let a = parse(candidate)
        let b = parse(current)
        let length = max(a.count, b.count)
        for i in 0..<length {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }
}
