import Foundation
import Protocols

struct ProjectMetaStore {
    let workspaceRootURL: URL
    let fileManager: FileManager

    init(workspaceRootURL: URL, fileManager: FileManager = .default) {
        self.workspaceRootURL = workspaceRootURL
        self.fileManager = fileManager
    }

    func projectDirectoryURL(projectID: String) -> URL {
        workspaceRootURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
    }

    func projectMetaURL(projectID: String) -> URL {
        projectDirectoryURL(projectID: projectID)
            .appendingPathComponent(".meta", isDirectory: true)
    }

    func initiativeDirectoryURL(projectID: String, initiativeID: String) -> URL {
        projectMetaURL(projectID: projectID)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent(initiativeID, isDirectory: true)
    }

    func ensureProjectMetaLayout(projectID: String) throws {
        let base = projectMetaURL(projectID: projectID)
        try fileManager.createDirectory(at: projectDirectoryURL(projectID: projectID), withIntermediateDirectories: true)
        for name in ["initiatives", "tasks", "artifacts", "decisions", "reviews", "state"] {
            try fileManager.createDirectory(
                at: base.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    @discardableResult
    func writeInitiativeArtifact(
        projectID: String,
        initiativeID: String,
        relativePath: String,
        content: Data
    ) throws -> URL {
        try ensureProjectMetaLayout(projectID: projectID)
        let fileURL = initiativeDirectoryURL(projectID: projectID, initiativeID: initiativeID)
            .appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, options: .atomic)
        return fileURL
    }

    @discardableResult
    func writeDecisionPacketMarkdown(projectID: String, packet: DecisionPacketRecord) throws -> URL {
        try ensureProjectMetaLayout(projectID: projectID)
        let fileURL = projectMetaURL(projectID: projectID)
            .appendingPathComponent("decisions", isDirectory: true)
            .appendingPathComponent("\(packet.id).md", isDirectory: false)

        let markdown = """
        # \(packet.summary)

        - Initiative ID: `\(packet.initiativeID)`
        - Status: `\(packet.status)`
        - Requested action: \(packet.requestedAction)

        ## Rationale

        \(packet.rationale)

        ## Tradeoffs

        \(packet.tradeoffs.isEmpty ? "- None." : packet.tradeoffs.map { "- \($0)" }.joined(separator: "\n"))

        ## Resume Point

        \(packet.resumePoint ?? "Not specified.")
        """

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(markdown.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    func initiativeActivitiesFileURL(projectID: String, initiativeID: String) -> URL {
        projectMetaURL(projectID: projectID)
            .appendingPathComponent("initiatives", isDirectory: true)
            .appendingPathComponent("\(initiativeID)-activity.json", isDirectory: false)
    }

    func listInitiativeArtifacts(projectID: String, initiativeID: String) -> [String] {
        let baseURL = initiativeDirectoryURL(projectID: projectID, initiativeID: initiativeID).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: baseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }
            let relative = url.standardizedFileURL.path
                .replacingOccurrences(of: baseURL.path + "/", with: "")
            result.append(relative)
        }
        return result.sorted()
    }

    func listInitiativeActivities(projectID: String, initiativeID: String) -> [InitiativeActivityRecord] {
        let url = initiativeActivitiesFileURL(projectID: projectID, initiativeID: initiativeID)
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([InitiativeActivityRecord].self, from: data)) ?? [])
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func saveInitiativeActivities(
        _ activities: [InitiativeActivityRecord],
        projectID: String,
        initiativeID: String
    ) throws {
        try ensureProjectMetaLayout(projectID: projectID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(activities)
        try data.write(to: initiativeActivitiesFileURL(projectID: projectID, initiativeID: initiativeID), options: .atomic)
    }
}
