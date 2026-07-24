import Foundation

struct ProjectContextLoader {
    struct Limits: Sendable {
        var maxSkillFiles: Int = 25
        var maxCharsPerFile: Int = 20_000
        var maxTotalChars: Int = 200_000
    }

    struct LoadedFile: Sendable {
        var relativePath: String
        var chars: Int
        var truncated: Bool
        var content: String
    }

    struct Result: Sendable {
        var repoPath: String
        var repoPaths: [String]
        var loadedDocs: [LoadedFile]
        var loadedProjectMemory: LoadedFile?
        var loadedSkills: [LoadedFile]
        var totalChars: Int
        var truncated: Bool
    }

    private let limits: Limits

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    func load(repoPath: String, projectMemoryURL: URL? = nil) -> Result {
        load(repoPaths: [repoPath], projectMemoryURL: projectMemoryURL)
    }

    func load(repoPaths: [String], projectMemoryURL: URL? = nil) -> Result {
        var seenRoots = Set<String>()
        let rootURLs = repoPaths.compactMap { raw -> URL? in
            let root = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
            let identity = root.resolvingSymlinksInPath().standardizedFileURL.path
            return seenRoots.insert(identity).inserted ? root : nil
        }
        var loadedDocs: [LoadedFile] = []
        var loadedProjectMemory: LoadedFile?
        var loadedSkills: [LoadedFile] = []
        var totalChars = 0
        var truncated = false

        func canAcceptMoreChars(_ additional: Int) -> Bool {
            totalChars + additional <= limits.maxTotalChars
        }

        func addFile(relativePath: String, content: String, to target: inout [LoadedFile]) {
            guard totalChars < limits.maxTotalChars else {
                truncated = true
                return
            }

            let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            let limited = String(normalized.prefix(limits.maxCharsPerFile))
            var finalContent = limited
            var didTruncate = limited.count < normalized.count

            let remaining = max(0, limits.maxTotalChars - totalChars)
            if finalContent.count > remaining {
                finalContent = String(finalContent.prefix(remaining))
                didTruncate = true
            }

            guard canAcceptMoreChars(finalContent.count) else {
                truncated = true
                return
            }

            target.append(
                LoadedFile(
                    relativePath: relativePath,
                    chars: finalContent.count,
                    truncated: didTruncate,
                    content: finalContent
                )
            )
            totalChars += finalContent.count
            if didTruncate {
                truncated = true
            }
        }

        func readTextFileIfExists(rootURL: URL, relativePath: String) -> String? {
            let url = rootURL.appendingPathComponent(relativePath).standardized
            let rootIdentity = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
            let fileIdentity = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard fileIdentity == rootIdentity || fileIdentity.hasPrefix(rootIdentity + "/") else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                return nil
            }
            guard let data = try? Data(contentsOf: url), data.count <= 2 * 1024 * 1024 else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }

        let docPaths: [String] = [
            "AGENTS.md",
            "USER.md",
            "SOUL.md",
            "CLAUDE.md",
            "GEMINI.md",
            "SLOPPY.md"
        ]
        for rootURL in rootURLs {
            for relativePath in docPaths {
                guard let text = readTextFileIfExists(rootURL: rootURL, relativePath: relativePath) else { continue }
                addFile(relativePath: rootURL.appendingPathComponent(relativePath).path, content: text, to: &loadedDocs)
            }
        }

        if let projectMemoryURL,
           let text = try? String(contentsOf: projectMemoryURL, encoding: .utf8) {
            var memoryDocs: [LoadedFile] = []
            addFile(relativePath: ".meta/MEMORY.md", content: text, to: &memoryDocs)
            loadedProjectMemory = memoryDocs.first
        }

        for rootURL in rootURLs where totalChars < limits.maxTotalChars {
            loadSkillFiles(
                rootURL: rootURL,
                maxFiles: max(0, limits.maxSkillFiles - loadedSkills.count),
                addFile: { relativePath, content in
                addFile(
                    relativePath: rootURL.appendingPathComponent(relativePath).path,
                    content: content,
                    to: &loadedSkills
                )
            }, recordTruncation: { truncated = true })
        }

        return Result(
            repoPath: rootURLs.first?.path ?? "",
            repoPaths: rootURLs.map(\.path),
            loadedDocs: loadedDocs,
            loadedProjectMemory: loadedProjectMemory,
            loadedSkills: loadedSkills,
            totalChars: totalChars,
            truncated: truncated
        )
    }

    private func loadSkillFiles(
        rootURL: URL,
        maxFiles: Int,
        addFile: (String, String) -> Void,
        recordTruncation: () -> Void
    ) {
        let skillsRoot = rootURL.appendingPathComponent(".skills", isDirectory: true).standardized
        guard skillsRoot.path.hasPrefix(rootURL.path) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: skillsRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        var skillPaths: [String] = []
        let fm = FileManager.default
        let rootIdentity = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        func collectSkills(in directory: URL) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            let children = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            )) ?? []
            for url in children {
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isSymbolicLink != true else { continue }
                let identity = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard identity == rootIdentity || identity.hasPrefix(rootIdentity + "/") else { continue }
                if values?.isDirectory == true {
                    collectSkills(in: url)
                } else if values?.isRegularFile == true, url.lastPathComponent == "SKILL.md" {
                    let relative = String(identity.dropFirst(rootIdentity.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    skillPaths.append(relative)
                }
            }
        }
        collectSkills(in: skillsRoot)

        skillPaths.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if skillPaths.count > maxFiles {
            recordTruncation()
            skillPaths = Array(skillPaths.prefix(maxFiles))
        }

        for relativePath in skillPaths {
            guard let text = try? String(contentsOf: rootURL.appendingPathComponent(relativePath), encoding: .utf8) else {
                continue
            }
            addFile(relativePath, text)
        }
    }
}
