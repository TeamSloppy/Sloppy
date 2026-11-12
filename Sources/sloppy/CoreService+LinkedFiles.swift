import Foundation
import Protocols

extension CoreService {
    /// Read-only preview of an absolute file link persisted in this conversation.
    /// Does not change project browsing roots or tool filesystem permissions.
    func readSessionLinkedFile(agentID: String, sessionID: String, path: String) async throws -> ProjectFileContentResponse {
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard let requested = SessionLinkedFilePath.absolutePath(path),
              detail.events.contains(where: { event in
                  guard event.agentId == agentID, event.sessionId == sessionID,
                        let message = event.message else { return false }
                  return message.segments.contains { segment in
                      guard let text = segment.text else { return false }
                      return SessionLinkedFilePath.links(in: text).contains(requested)
                  }
              }) else { throw AgentSessionError.sessionNotFound }
        let url = URL(fileURLWithPath: requested)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try WorkspaceFilePreview.read(url: url, path: requested)
            }.value
        } catch { throw AgentSessionError.sessionNotFound }
    }
}

/// Parses link destinations, never arbitrary mentions or tool output. A link grants
/// preview of that exact lexical path, not its directory or a symlink alias.
enum SessionLinkedFilePath {
    static func absolutePath(_ value: String) -> String? {
        guard value.hasPrefix("/"), !value.hasPrefix("//"),
              !value.contains("\0"), !value.contains("\n"), !value.contains("\r"),
              !value.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    static func links(in text: String) -> Set<String> {
        // Inline Markdown, angle-quoted destinations (spaces), and autolinks.
        let pattern = #"\]\(\s*(?:<([^>\r\n]+)>|([^\s)]+))(?:\s+"[^"]*")?\s*\)|<(file://[^>\r\n]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var paths = Set<String>()
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            for index in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: index), in: text),
                      let path = destinationPath(String(text[range])) else { continue }
                paths.insert(path)
            }
        }
        return paths
    }

    static func destinationPath(_ destination: String) -> String? {
        guard let url = URL(string: destination),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil,
              (components.scheme == nil && components.host == nil) ||
                (url.isFileURL && [nil, "", "localhost"].contains(components.host)) else { return nil }
        var path = components.path
        if let suffix = path.range(of: #":([0-9]+)(?::([0-9]+))?$"#, options: .regularExpression) {
            path = String(path[..<suffix.lowerBound])
        }
        if let fragment = components.fragment,
           fragment.range(of: #"^L[0-9]+(?:-L?[0-9]+)?$"#, options: .regularExpression) == nil { return nil }
        return absolutePath(path)
    }
}
