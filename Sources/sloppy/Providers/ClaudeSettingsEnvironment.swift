import Foundation

struct ClaudeSettingsEnvironment: Sendable, Equatable {
    var baseURLString: String?
    var authToken: String?

    var baseURL: URL? {
        guard let baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    var hasAuthToken: Bool {
        !(authToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        workspaceRootURL: URL? = nil,
        currentDirectoryURL: URL? = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> ClaudeSettingsEnvironment {
        load(from: settingsURLs(
            workspaceRootURL: workspaceRootURL,
            currentDirectoryURL: currentDirectoryURL,
            homeDirectoryURL: homeDirectoryURL
        ), fileManager: fileManager)
    }

    static func load(from urls: [URL], fileManager: FileManager = .default) -> ClaudeSettingsEnvironment {
        var resolved = ClaudeSettingsEnvironment()
        for url in urls {
            guard let settings = load(from: url, fileManager: fileManager) else { continue }
            if resolved.baseURLString == nil {
                resolved.baseURLString = settings.baseURLString
            }
            if resolved.authToken == nil {
                resolved.authToken = settings.authToken
            }
            if resolved.baseURLString != nil, resolved.authToken != nil {
                break
            }
        }
        return resolved
    }

    static func load(from url: URL, fileManager: FileManager = .default) -> ClaudeSettingsEnvironment? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = object["env"] as? [String: Any]
        else {
            return nil
        }

        let baseURL = stringValue(env["ANTHROPIC_BASE_URL"])
        let authToken = stringValue(env["ANTHROPIC_AUTH_TOKEN"])
        guard baseURL != nil || authToken != nil else { return nil }

        return ClaudeSettingsEnvironment(baseURLString: baseURL, authToken: authToken)
    }

    private static func settingsURLs(
        workspaceRootURL: URL?,
        currentDirectoryURL: URL?,
        homeDirectoryURL: URL
    ) -> [URL] {
        var urls: [URL] = []
        if let workspaceRootURL {
            urls.append(settingsURL(root: workspaceRootURL))
        }
        if let currentDirectoryURL {
            urls.append(settingsURL(root: currentDirectoryURL))
        }
        urls.append(settingsURL(root: homeDirectoryURL))
        return urls.removingDuplicatesByStandardizedPath()
    }

    private static func settingsURL(root: URL) -> URL {
        root
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private static func stringValue(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == URL {
    func removingDuplicatesByStandardizedPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
