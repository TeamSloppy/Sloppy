import Foundation
import Protocols

extension CoreService {
    public func resolveOrCreateProjectForCurrentDirectory(_ cwd: String = FileManager.default.currentDirectoryPath) async throws -> ProjectRecord {
        let cwdPath = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
        let projects = await listProjects()
        if let existing = projects.first(where: { project in
            guard let repoPath = project.repoPath?.trimmingCharacters(in: .whitespacesAndNewlines), !repoPath.isEmpty else {
                return false
            }
            return URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path == cwdPath
        }) {
            return existing
        }

        let folderName = URL(fileURLWithPath: cwdPath, isDirectory: true).lastPathComponent
        let baseID = normalizedProjectID(slugify(folderName)) ?? "project"
        let existingIDs = Set(projects.map(\.id))
        let projectID: String
        if existingIDs.contains(baseID) {
            let suffix = shortStablePathHash(cwdPath)
            projectID = "\(baseID)-\(suffix)"
        } else {
            projectID = baseID
        }

        let created = try await createProject(
            ProjectCreateRequest(
                id: projectID,
                name: folderName.isEmpty ? projectID : folderName,
                description: "Local project opened from \(cwdPath)",
                channels: [],
                repoPath: cwdPath
            )
        )
        return created.project
    }

    public func streamProjectWorkingTreeChanges(projectID: String) async throws -> AsyncStream<ProjectWorkingTreeChangeBatch> {
        let normalizedID = normalizedProjectID(projectID) ?? projectID
        let rootURL = try await resolveProjectWorkspaceRoot(projectID: normalizedID)
        return ProjectChangeWatcherService().stream(projectID: normalizedID, rootURL: rootURL)
    }

    nonisolated func shortStablePathHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%08llx", hash).prefix(8).description
    }
}
