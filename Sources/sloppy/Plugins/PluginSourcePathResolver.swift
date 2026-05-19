import Foundation

enum PluginSourcePathResolver {
    static func installRequestSource(
        from source: String,
        localDirectory: Bool?,
        fileManager: FileManager = .default,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> String {
        if localDirectory == true || looksLikeLocalDirectorySource(source) {
            return localDirectoryURL(from: source, currentDirectoryPath: currentDirectoryPath).path
        }

        guard localDirectory == nil else {
            return source
        }

        let sourceURL = localDirectoryURL(from: source, currentDirectoryPath: currentDirectoryPath)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return sourceURL.path
        }
        return source
    }

    static func shouldCopyLocalDirectory(
        source: String,
        localDirectory: Bool?,
        fileManager: FileManager = .default,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> Bool {
        if let localDirectory {
            return localDirectory
        }
        if looksLikeLocalDirectorySource(source) {
            return true
        }
        let sourceURL = localDirectoryURL(from: source, currentDirectoryPath: currentDirectoryPath)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func localDirectoryURL(
        from source: String,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> URL {
        if let url = URL(string: source), url.isFileURL {
            return url.standardizedFileURL
        }

        let expanded = (source as NSString).expandingTildeInPath
        if expanded.starts(with: "/") {
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        let cwd = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let resolved = (cwd.path as NSString).appendingPathComponent(expanded)
        return URL(fileURLWithPath: resolved, isDirectory: true).standardizedFileURL
    }

    static func looksLikeLocalDirectorySource(_ source: String) -> Bool {
        source == "."
            || source == ".."
            || source.starts(with: "/")
            || source.starts(with: "~")
            || source.starts(with: "./")
            || source.starts(with: "../")
            || source.starts(with: "file://")
            || source.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }
}
