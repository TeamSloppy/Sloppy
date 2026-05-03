import Foundation
import Protocols

struct ProjectChangeWatcherConfiguration: Sendable {
    var pollIntervalNanoseconds: UInt64
    var debounceNanoseconds: UInt64
    var maximumFiles: Int
    var excludedDirectoryNames: Set<String>

    init(
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        debounceNanoseconds: UInt64 = 350_000_000,
        maximumFiles: Int = 80_000,
        excludedDirectoryNames: Set<String> = ProjectChangeWatcherService.defaultExcludedDirectoryNames
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.debounceNanoseconds = debounceNanoseconds
        self.maximumFiles = maximumFiles
        self.excludedDirectoryNames = excludedDirectoryNames
    }
}

struct ProjectFileSnapshot: Equatable, Sendable {
    var sizeBytes: Int?
    var modifiedAt: Date?
}

struct ProjectChangeWatcherService: @unchecked Sendable {
    static let defaultExcludedDirectoryNames: Set<String> = [
        ".git",
        ".sloppy",
        ".sloppy-worktrees",
        ".build",
        "node_modules",
        "dist",
        "DerivedData",
    ]

    var configuration: ProjectChangeWatcherConfiguration
    var fileManager: FileManager

    init(
        configuration: ProjectChangeWatcherConfiguration = ProjectChangeWatcherConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func snapshot(rootURL: URL) -> [String: ProjectFileSnapshot] {
        var result: [String: ProjectFileSnapshot] = [:]
        var visited = 0
        walk(directoryURL: rootURL.standardizedFileURL, relativeDirectory: "", result: &result, visited: &visited)
        return result
    }

    func changes(
        projectID: String,
        rootURL: URL,
        previous: [String: ProjectFileSnapshot],
        current: [String: ProjectFileSnapshot],
        createdAt: Date = Date()
    ) -> ProjectWorkingTreeChangeBatch? {
        var entries: [ProjectWorkingTreeChange] = []
        let allPaths = Set(previous.keys).union(current.keys)

        for path in allPaths.sorted() {
            let old = previous[path]
            let new = current[path]
            if old == nil, let new {
                entries.append(.init(path: path, kind: .created, sizeBytes: new.sizeBytes, modifiedAt: new.modifiedAt))
            } else if let old, new == nil {
                entries.append(.init(path: path, kind: .deleted, sizeBytes: old.sizeBytes, modifiedAt: old.modifiedAt))
            } else if let old, let new, old != new {
                entries.append(.init(path: path, kind: .modified, sizeBytes: new.sizeBytes, modifiedAt: new.modifiedAt))
            }
        }

        guard !entries.isEmpty else {
            return nil
        }

        return ProjectWorkingTreeChangeBatch(
            projectId: projectID,
            rootPath: rootURL.standardizedFileURL.path,
            changes: entries,
            createdAt: createdAt
        )
    }

    func stream(projectID: String, rootURL: URL) -> AsyncStream<ProjectWorkingTreeChangeBatch> {
        AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            let task = Task {
                var previous = snapshot(rootURL: rootURL)

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: configuration.pollIntervalNanoseconds)
                    if Task.isCancelled {
                        break
                    }

                    let current = snapshot(rootURL: rootURL)
                    guard let firstBatch = changes(projectID: projectID, rootURL: rootURL, previous: previous, current: current) else {
                        previous = current
                        continue
                    }

                    try? await Task.sleep(nanoseconds: configuration.debounceNanoseconds)
                    if Task.isCancelled {
                        break
                    }

                    let settled = snapshot(rootURL: rootURL)
                    if let debounced = changes(projectID: projectID, rootURL: rootURL, previous: previous, current: settled) {
                        continuation.yield(debounced)
                        previous = settled
                    } else {
                        continuation.yield(firstBatch)
                        previous = current
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func walk(
        directoryURL: URL,
        relativeDirectory: String,
        result: inout [String: ProjectFileSnapshot],
        visited: inout Int
    ) {
        guard visited < configuration.maximumFiles else {
            return
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        )) ?? []

        for url in urls {
            guard visited < configuration.maximumFiles else {
                return
            }

            let name = url.lastPathComponent
            let relativePath = relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                guard !configuration.excludedDirectoryNames.contains(name) else {
                    continue
                }
                walk(directoryURL: url, relativeDirectory: relativePath, result: &result, visited: &visited)
            } else {
                visited += 1
                result[relativePath] = ProjectFileSnapshot(
                    sizeBytes: values?.fileSize,
                    modifiedAt: values?.contentModificationDate
                )
            }
        }
    }
}
