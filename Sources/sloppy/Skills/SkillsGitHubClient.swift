import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for downloading skill files from GitHub repositories
actor SkillsGitHubClient {
    enum ClientError: Error {
        case invalidURL
        case invalidRepository
        case networkError(Error)
        case httpError(Int, String?)
        case decodeError
        case fileWriteError(Error)
        case invalidResponse
        case contentNotFound
    }

    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let tokenProvider: @Sendable () -> String?

    init(urlSession: URLSession = SloppyURLSessionFactory.shared, tokenProvider: (@Sendable () -> String?)? = nil) {
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.tokenProvider = tokenProvider ?? {
            let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ""
            return token.isEmpty ? nil : token
        }
    }

    // MARK: - Public API

    /// Download a skill from GitHub repository
    /// Downloads the repository content and extracts skill files
    func downloadSkill(
        owner: String,
        repo: String,
        version: String? = nil,
        destination: URL
    ) async throws -> DownloadedSkill {
        // Validate inputs
        let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedOwner.isEmpty, !normalizedRepo.isEmpty else {
            throw ClientError.invalidRepository
        }

        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = (trimmedVersion?.isEmpty == false) ? trimmedVersion : nil

        // First, try to get the repository contents
        let contents = try await fetchRepositoryContents(
            owner: normalizedOwner,
            repo: normalizedRepo,
            path: "",
            ref: ref
        )

        // Create destination directory
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var downloadedFiles: [String] = []
        var skillName = normalizedRepo
        var skillDescription: String?
        var skillFrontmatter: SkillFrontmatter?

        // Look for common skill files
        let skillFiles = contents.filter { item in
            let name = item.name.lowercased()
            return name.hasSuffix(".md") ||
                   name == "skill.json" ||
                   name == "package.json" ||
                   name.hasPrefix("skill") ||
                   name.hasPrefix("prompt")
        }

        for item in skillFiles {
            do {
                let fileURL = destination.appendingPathComponent(item.name)

                if item.type == "file" {
                    guard let downloadURL = item.downloadUrl else {
                        continue
                    }

                    try await downloadFile(from: downloadURL, to: fileURL)
                    downloadedFiles.append(item.name)

                    if item.name.lowercased() == "skill.json" {
                        if let metadata = try? extractSkillMetadata(from: fileURL) {
                            skillName = metadata.name ?? skillName
                            skillDescription = metadata.description
                        }
                    } else if item.name.lowercased() == "skill.md" {
                        if let mdContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            if let fm = Self.parseFrontmatter(from: mdContent) {
                                skillFrontmatter = fm
                                if let fmName = fm.name, !fmName.isEmpty {
                                    skillName = fmName
                                }
                                if let fmDesc = fm.description, !fmDesc.isEmpty {
                                    skillDescription = fmDesc
                                }
                            }
                        }
                    } else if item.name.lowercased() == "readme.md" {
                        if let readmeContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            skillDescription = extractDescriptionFromReadme(readmeContent)
                        }
                    }
                } else if item.type == "dir" {
                    // Recursively download subdirectory
                    let subDir = destination.appendingPathComponent(item.name)
                    let subFiles = try await downloadDirectory(
                        owner: normalizedOwner,
                        repo: normalizedRepo,
                        path: item.path,
                        ref: ref,
                        destination: subDir
                    )
                    downloadedFiles.append(contentsOf: subFiles.map { "\(item.name)/\($0)" })
                }
            } catch {
                // Continue with other files if one fails
                continue
            }
        }

        guard !downloadedFiles.isEmpty else {
            throw ClientError.contentNotFound
        }

        let entrypoint = resolveSkillEntrypoint(
            destination: destination,
            downloadedFiles: downloadedFiles,
            repo: normalizedRepo
        )
        if let entrypoint {
            skillFrontmatter = entrypoint.frontmatter ?? skillFrontmatter
            if let fmName = entrypoint.frontmatter?.name, !fmName.isEmpty {
                skillName = fmName
            }
            if let fmDesc = entrypoint.frontmatter?.description, !fmDesc.isEmpty {
                skillDescription = fmDesc
            }
        }

        return DownloadedSkill(
            owner: normalizedOwner,
            repo: normalizedRepo,
            name: skillName,
            description: skillDescription,
            version: ref ?? "default",
            files: downloadedFiles,
            localPath: entrypoint?.directory.path ?? destination.path,
            frontmatter: skillFrontmatter
        )
    }

    /// Install a skill from a local directory by copying it into the agent skills store.
    func installLocalSkill(
        sourcePath: String,
        destination: URL,
        owner requestedOwner: String? = nil,
        repo requestedRepo: String? = nil
    ) throws -> DownloadedSkill {
        let source = URL(fileURLWithPath: sourcePath.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ClientError.contentNotFound
        }

        let skillFiles = try localSkillFiles(in: source)
        guard !skillFiles.isEmpty else {
            throw ClientError.contentNotFound
        }

        let normalizedRepoHint = requestedRepo?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entrypoint = resolveSkillEntrypoint(
            destination: source,
            downloadedFiles: skillFiles,
            repo: normalizedRepoHint?.isEmpty == false ? normalizedRepoHint! : source.lastPathComponent
        ) else {
            throw ClientError.contentNotFound
        }

        let fm = entrypoint.frontmatter
        let derivedName = fm?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = normalizedRepoHint?.isEmpty == false
            ? normalizedRepoHint!
            : Self.skillIDComponent(from: derivedName ?? source.lastPathComponent)
        let owner = {
            let raw = requestedOwner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "local" : raw
        }()

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)

        let relativeEntrypoint = entrypoint.directory.standardizedFileURL.path
            .dropFirst(source.path.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let storedEntrypoint = relativeEntrypoint.isEmpty
            ? destination
            : destination.appendingPathComponent(relativeEntrypoint, isDirectory: true)

        let name = derivedName?.isEmpty == false ? derivedName! : repo
        let description = fm?.description?.trimmingCharacters(in: .whitespacesAndNewlines)

        return DownloadedSkill(
            owner: owner,
            repo: repo,
            name: name,
            description: description?.isEmpty == false ? description : nil,
            version: "local",
            files: skillFiles,
            localPath: storedEntrypoint.standardizedFileURL.path,
            frontmatter: fm
        )
    }

    /// Get the raw URL for a specific file in a repository
    func rawFileURL(
        owner: String,
        repo: String,
        path: String,
        ref: String = "main"
    ) -> URL? {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref)/\(encodedPath)")
    }

    // MARK: - Private Helpers

    private func localSkillFiles(in source: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ClientError.contentNotFound
        }

        var files: [String] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.standardizedFileURL.path
                .dropFirst(source.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relative.isEmpty {
                files.append(relative)
            }
        }
        return files.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func skillIDComponent(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        var result = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "skill" : result
    }

    private func fetchRepositoryContents(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> [GitHubContentItem] {
        var urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents"
        if !path.isEmpty {
            urlString += "/\(path)"
        }
        if let ref, !ref.isEmpty {
            urlString += "?ref=\(ref)"
        }

        guard let url = URL(string: urlString) else {
            throw ClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                // Single file or directory
                if let items = try? decoder.decode([GitHubContentItem].self, from: data) {
                    return items
                } else if let item = try? decoder.decode(GitHubContentItem.self, from: data) {
                    return [item]
                } else {
                    throw ClientError.decodeError
                }
            case 401:
                throw ClientError.httpError(401, "Unauthorized")
            case 403:
                throw ClientError.httpError(403, "Rate limited or forbidden")
            case 404:
                throw ClientError.httpError(404, "Repository or path not found")
            default:
                throw ClientError.httpError(httpResponse.statusCode, nil)
            }
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.networkError(error)
        }
    }

    private func downloadDirectory(
        owner: String,
        repo: String,
        path: String,
        ref: String?,
        destination: URL
    ) async throws -> [String] {
        let contents = try await fetchRepositoryContents(
            owner: owner,
            repo: repo,
            path: path,
            ref: ref
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var downloadedFiles: [String] = []

        for item in contents {
            let fileURL = destination.appendingPathComponent(item.name)

            if item.type == "file" {
                guard let downloadURL = item.downloadUrl else {
                    continue
                }
                do {
                    try await downloadFile(from: downloadURL, to: fileURL)
                    downloadedFiles.append(item.name)
                } catch {
                    continue
                }
            } else if item.type == "dir" {
                let subDir = destination.appendingPathComponent(item.name)
                let subFiles = try await downloadDirectory(
                    owner: owner,
                    repo: repo,
                    path: item.path,
                    ref: ref,
                    destination: subDir
                )
                downloadedFiles.append(contentsOf: subFiles.map { "\(item.name)/\($0)" })
            }
        }

        return downloadedFiles
    }

    private func downloadFile(from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw ClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpError(httpResponse.statusCode, nil)
            }

            try data.write(to: destination)
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.fileWriteError(error)
        }
    }

    private func extractSkillMetadata(from url: URL) throws -> SkillMetadata {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SkillMetadata.self, from: data)
    }

    private func extractDescriptionFromReadme(_ content: String) -> String? {
        // Extract first paragraph that looks like a description
        let lines = content.components(separatedBy: .newlines)

        // Skip the title line (# Title)
        var foundTitle = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("# ") {
                foundTitle = true
                continue
            }

            if foundTitle && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                // Return first non-empty, non-header line
                return trimmed
            }
        }

        return nil
    }

    private func resolveSkillEntrypoint(destination: URL, downloadedFiles: [String], repo: String) -> SkillEntrypoint? {
        let skillFiles = downloadedFiles
            .filter { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "skill.md" }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !skillFiles.isEmpty else {
            return nil
        }

        let normalizedRepo = repo.lowercased()
        let selectedPath =
            skillFiles.first { $0.lowercased() == "skill.md" } ??
            skillFiles.first { path in
                path.lowercased() == "skills/\(normalizedRepo)/skill.md"
            } ??
            skillFiles.first { path in
                path.lowercased() == "\(normalizedRepo)/skill.md"
            } ??
            skillFiles.first { path in
                let components = path
                    .split(separator: "/")
                    .map { String($0).lowercased() }
                guard components.last == "skill.md" else { return false }
                return zip(components, components.dropFirst()).contains { lhs, rhs in
                    lhs == "skills" && rhs == normalizedRepo
                }
            } ??
            (skillFiles.count == 1 ? skillFiles[0] : nil)

        guard let selectedPath else {
            return nil
        }

        let skillFile = destination.appendingPathComponent(selectedPath)
        let directory = skillFile.deletingLastPathComponent()
        let frontmatter: SkillFrontmatter?
        if let markdown = try? String(contentsOf: skillFile, encoding: .utf8) {
            frontmatter = Self.parseFrontmatter(from: markdown)
        } else {
            frontmatter = nil
        }
        return SkillEntrypoint(directory: directory, frontmatter: frontmatter)
    }
}

// MARK: - Supporting Types

extension SkillsGitHubClient {
    struct GitHubContentItem: Codable {
        let name: String
        let path: String
        let type: String // "file" or "dir"
        // GitHub returns `null` for directories.
        let downloadUrl: String?

        enum CodingKeys: String, CodingKey {
            case name
            case path
            case type
            case downloadUrl = "download_url"
        }
    }

    struct SkillMetadata: Codable {
        let name: String?
        let description: String?
        let version: String?
    }

    struct SkillFrontmatter {
        var name: String?
        var description: String?
        var userInvocable: Bool?
        var allowedTools: [String]?
        var context: String?
        var agent: String?
        var autoRoute: String?
    }

    struct SkillEntrypoint {
        var directory: URL
        var frontmatter: SkillFrontmatter?
    }

    struct DownloadedSkill {
        let owner: String
        let repo: String
        let name: String
        let description: String?
        let version: String
        let files: [String]
        let localPath: String
        var frontmatter: SkillFrontmatter?
    }

    static func parseFrontmatter(from content: String) -> SkillFrontmatter? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return nil }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return nil }

        var fm = SkillFrontmatter()
        var i = 1
        while i < end {
            let line = lines[i]
            guard let colonIndex = line.firstIndex(of: ":") else {
                i += 1
                continue
            }
            let key = line[line.startIndex..<colonIndex]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
            var value = line[line.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)
            i += 1

            if value == ">" || value == "|" {
                let blockStyle = value
                var blockLines: [String] = []
                while i < end {
                    let nextLine = lines[i]
                    if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        blockLines.append("")
                        i += 1
                        continue
                    }
                    guard nextLine.first?.isWhitespace == true else {
                        break
                    }
                    blockLines.append(nextLine.trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                if blockStyle == ">" {
                    value = blockLines
                        .joined(separator: " ")
                        .replacingOccurrences(
                            of: #"\s+"#,
                            with: " ",
                            options: .regularExpression
                        )
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    value = blockLines.joined(separator: "\n")
                }
            }

            switch key {
            case "name":
                fm.name = value
            case "description":
                fm.description = value
            case "user_invocable", "userinvocable":
                fm.userInvocable = value.lowercased() == "true"
            case "allowed_tools", "allowedtools":
                fm.allowedTools = value
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "context":
                fm.context = value
            case "agent":
                fm.agent = value
            case "auto_route", "autoroute", "use_when", "usewhen":
                fm.autoRoute = value
            default:
                break
            }
        }
        return fm
    }
}

extension SkillsGitHubClient.ClientError {
    /// Stable, log-friendly description (no PII beyond repo-related HTTP messages).
    var logDescription: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .invalidRepository:
            return "invalid_repository"
        case .networkError(let err):
            return "network_error: \(err.localizedDescription)"
        case .httpError(let code, let body):
            let raw = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = raw.count > 500 ? String(raw.prefix(500)) + "…" : raw
            return snippet.isEmpty ? "http_\(code)" : "http_\(code): \(snippet)"
        case .decodeError:
            return "decode_error"
        case .fileWriteError(let err):
            return "file_write: \(err.localizedDescription)"
        case .invalidResponse:
            return "invalid_response"
        case .contentNotFound:
            return "content_not_found"
        }
    }
}
