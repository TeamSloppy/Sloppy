import Foundation
import Logging
import Protocols

enum WorkspaceGitSyncError: LocalizedError {
    case disabled
    case missingRepository
    case gitUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Workspace Git Sync is disabled."
        case .missingRepository:
            return "Workspace Git Sync repository is not configured."
        case .gitUnavailable:
            return "git is not available on the system."
        case .commandFailed(let message):
            return message
        }
    }
}

struct WorkspaceGitSyncService: Sendable {
    private static let excludedDirectories: Set<String> = [
        ".git",
        ".git-sync",
        ".meta",
        "auth",
        "channel-sessions",
        "logs",
        "memory",
        "node_modules",
        "projects",
        "sessions"
    ]

    private static let excludedFiles: Set<String> = [
        ".DS_Store",
        "core.sqlite",
        "core.sqlite-shm",
        "core.sqlite-wal",
        "pending_approval.json"
    ]

    private let logger = Logger(label: "sloppy.core.git-sync")

    func syncNow(config: CoreConfig.GitSync, workspaceRootURL: URL) async throws -> WorkspaceGitSyncResponse {
        guard config.enabled else {
            throw WorkspaceGitSyncError.disabled
        }

        let repository = config.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw WorkspaceGitSyncError.missingRepository
        }

        let branch = config.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "main"
            : config.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteURL = authenticatedRemoteURL(
            repositoryURL(repository),
            token: config.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let syncRootURL = workspaceRootURL.appendingPathComponent(".git-sync", isDirectory: true)
        let checkoutURL = syncRootURL.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: syncRootURL, withIntermediateDirectories: true)

        if !isGitCheckout(checkoutURL) {
            if FileManager.default.fileExists(atPath: checkoutURL.path) {
                try FileManager.default.removeItem(at: checkoutURL)
            }
            try await git(["clone", remoteURL, checkoutURL.path], cwd: syncRootURL)
        }

        try await git(["remote", "set-url", "origin", remoteURL], cwd: checkoutURL)
        _ = try? await git(["fetch", "origin", branch], cwd: checkoutURL)

        if try await remoteBranchExists(branch: branch, cwd: checkoutURL) {
            switch config.conflictStrategy {
            case .remoteWins:
                try await git(["checkout", "-B", branch, "origin/\(branch)"], cwd: checkoutURL)
                try await git(["reset", "--hard", "origin/\(branch)"], cwd: checkoutURL)
            case .localWins:
                try await git(["checkout", "-B", branch], cwd: checkoutURL)
            case .manual:
                try await ensureNotDiverged(branch: branch, cwd: checkoutURL)
                try await git(["checkout", "-B", branch, "origin/\(branch)"], cwd: checkoutURL)
            }
        } else {
            try await git(["checkout", "-B", branch], cwd: checkoutURL)
        }

        try replaceCheckoutContents(from: workspaceRootURL, to: checkoutURL)
        try await git(["add", "-A"], cwd: checkoutURL)

        let filesChanged = try await changedFileCount(cwd: checkoutURL)
        guard filesChanged > 0 else {
            let commit = try? await gitOutput(["rev-parse", "--short", "HEAD"], cwd: checkoutURL)
            return WorkspaceGitSyncResponse(
                ok: true,
                message: "Workspace Git Sync is already up to date.",
                branch: branch,
                commit: commit,
                filesChanged: 0
            )
        }

        try await ensureGitIdentity(cwd: checkoutURL)
        try await git(["commit", "-m", "Sync Sloppy workspace configuration"], cwd: checkoutURL)

        let pushArgs: [String]
        if config.conflictStrategy == .localWins {
            pushArgs = ["push", "--force-with-lease", "origin", branch]
        } else {
            pushArgs = ["push", "-u", "origin", branch]
        }
        try await git(pushArgs, cwd: checkoutURL)

        let commit = try? await gitOutput(["rev-parse", "--short", "HEAD"], cwd: checkoutURL)
        logger.info(
            "workspace_git_sync.completed",
            metadata: [
                "branch": .string(branch),
                "files_changed": .stringConvertible(filesChanged)
            ]
        )
        return WorkspaceGitSyncResponse(
            ok: true,
            message: "Workspace Git Sync completed.",
            branch: branch,
            commit: commit,
            filesChanged: filesChanged
        )
    }

    private func repositoryURL(_ raw: String) -> String {
        if raw.hasPrefix("git@") || raw.hasPrefix("ssh://") || raw.hasPrefix("https://") ||
            raw.hasPrefix("http://") || raw.hasPrefix("file://") || raw.hasPrefix("/") ||
            raw.hasPrefix("./") || raw.hasPrefix("../") {
            return raw
        }

        let parts = raw.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count == 2 {
            return "https://github.com/\(parts[0])/\(parts[1]).git"
        }
        return raw
    }

    private func authenticatedRemoteURL(_ raw: String, token: String) -> String {
        guard !token.isEmpty,
              var components = URLComponents(string: raw),
              components.scheme == "https",
              components.host?.lowercased() == "github.com"
        else {
            return raw
        }
        components.user = "x-access-token"
        components.password = token
        return components.string ?? raw
    }

    private func isGitCheckout(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    private func remoteBranchExists(branch: String, cwd: URL) async throws -> Bool {
        let result = try await runGit(["rev-parse", "--verify", "origin/\(branch)"], cwd: cwd)
        return result.exitCode == 0
    }

    private func ensureNotDiverged(branch: String, cwd: URL) async throws {
        let local = try await gitOutput(["rev-parse", branch], cwd: cwd)
        let remote = try await gitOutput(["rev-parse", "origin/\(branch)"], cwd: cwd)
        if local != remote {
            throw WorkspaceGitSyncError.commandFailed(
                "Workspace Git Sync stopped because local checkout differs from origin/\(branch)."
            )
        }
    }

    private func replaceCheckoutContents(from workspaceRootURL: URL, to checkoutURL: URL) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(
            at: checkoutURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            if item.lastPathComponent != ".git" {
                try fileManager.removeItem(at: item)
            }
        }

        let rootItems = try fileManager.contentsOfDirectory(
            at: workspaceRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for item in rootItems {
            let name = item.lastPathComponent
            guard shouldInclude(name: name, url: item) else { continue }
            let destination = checkoutURL.appendingPathComponent(name, isDirectory: isDirectory(item))
            try copyWorkspaceItem(item, to: destination, relativePath: name)
        }
    }

    private func copyWorkspaceItem(_ source: URL, to destination: URL, relativePath: String) throws {
        let fileManager = FileManager.default
        if isDirectory(source) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            for child in children {
                let name = child.lastPathComponent
                guard shouldInclude(name: name, url: child) else { continue }
                let childRelativePath = "\(relativePath)/\(name)"
                let childDestination = destination.appendingPathComponent(name, isDirectory: isDirectory(child))
                try copyWorkspaceItem(child, to: childDestination, relativePath: childRelativePath)
            }
            return
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if relativePath == "sloppy.json" {
            let data = try Data(contentsOf: source)
            let sanitized = sanitizeConfigJSON(data) ?? data
            try sanitized.write(to: destination, options: .atomic)
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func shouldInclude(name: String, url: URL) -> Bool {
        if isDirectory(url) {
            return !Self.excludedDirectories.contains(name)
        }
        return !Self.excludedFiles.contains(name) && !name.hasSuffix(".sqlite") &&
            !name.hasSuffix(".sqlite-shm") && !name.hasSuffix(".sqlite-wal") &&
            !name.hasSuffix(".log")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func sanitizeConfigJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let sanitized = sanitizeJSONValue(object)
        return try? JSONSerialization.data(
            withJSONObject: sanitized,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func sanitizeJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, rawValue) in dict {
                sanitized[key] = shouldRedactConfigKey(key) ? "" : sanitizeJSONValue(rawValue)
            }
            return sanitized
        }
        if let array = value as? [Any] {
            return array.map { sanitizeJSONValue($0) }
        }
        return value
    }

    private func shouldRedactConfigKey(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
        return normalized.contains("token") ||
            normalized.contains("apikey") ||
            normalized.contains("password") ||
            normalized.contains("secret")
    }

    private func changedFileCount(cwd: URL) async throws -> Int {
        let status = try await gitOutput(["status", "--porcelain"], cwd: cwd)
        return status.split(separator: "\n").count
    }

    private func ensureGitIdentity(cwd: URL) async throws {
        let email = try? await gitOutput(["config", "user.email"], cwd: cwd)
        if email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            try await git(["config", "user.email", "sloppy-sync@localhost"], cwd: cwd)
        }
        let name = try? await gitOutput(["config", "user.name"], cwd: cwd)
        if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            try await git(["config", "user.name", "Sloppy Git Sync"], cwd: cwd)
        }
    }

    private func gitOutput(_ args: [String], cwd: URL) async throws -> String {
        let result = try await runGit(args, cwd: cwd)
        guard result.exitCode == 0 else {
            throw WorkspaceGitSyncError.commandFailed(result.output)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func git(_ args: [String], cwd: URL) async throws {
        let result = try await runGit(args, cwd: cwd)
        guard result.exitCode == 0 else {
            throw WorkspaceGitSyncError.commandFailed(result.output)
        }
    }

    private func runGit(_ args: [String], cwd: URL) async throws -> (exitCode: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = cwd
            process.environment = childProcessEnvironment()

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: WorkspaceGitSyncError.gitUnavailable)
                return
            }

            process.waitUntilExit()
            let output = [
                String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            continuation.resume(returning: (process.terminationStatus, output))
        }
    }
}
