import Foundation

/// A dashboard workflow route, rather than a path in the project's filesystem.
public struct ProjectWorkflowReference: Equatable, Sendable {
    public let projectID: String
    public let workflowID: String

    public init?(path: String) {
        guard let url = URL(string: path), url.scheme == nil, url.host == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "projects", parts[3] == "workflows",
              !parts[2].isEmpty, !parts[4].isEmpty else { return nil }
        projectID = String(parts[2])
        workflowID = String(parts[4])
    }
}
