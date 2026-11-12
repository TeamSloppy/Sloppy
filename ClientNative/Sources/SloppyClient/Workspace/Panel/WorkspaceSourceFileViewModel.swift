import Foundation
import Observation
import ImageIO
import SloppyClientCore
import Textual

@Observable
@MainActor
final class WorkspaceSourceFileViewModel {
    enum Scope: Equatable {
        case project(String)
        case agent(String)
        case session(agentID: String, sessionID: String)
        case unavailable
    }

    let apiClient: SloppyAPIClient
    let scope: Scope
    private(set) var reference: SourceFileReference
    private(set) var content: ProjectFileContentResponse?
    private(set) var lines: [String] = []
    private(set) var syntaxLines: [[SourceSyntaxRun]] = []
    private(set) var image: CGImage?
    private(set) var isLoading = false
    private var activeLoadID: UUID?
    private(set) var errorMessage: String?
    private(set) var navigationRevision = 0
    private(set) var loadRevision = 0

    init(reference: SourceFileReference, apiClient: SloppyAPIClient, scope: Scope) {
        self.reference = reference
        self.apiClient = apiClient
        self.scope = scope
    }

    var title: String { URL(fileURLWithPath: reference.path).lastPathComponent }
    var targetLine: Int { min(max(reference.line ?? 1, 1), max(lines.count, 1)) }
    var isLineOutsideFile: Bool { reference.line.map { $0 > lines.count } ?? false }

    func navigate(to reference: SourceFileReference) {
        guard self.reference.path == reference.path else { return }
        self.reference = reference
        navigationRevision += 1
    }

    func reload() {
        activeLoadID = nil
        isLoading = false
        content = nil
        image = nil
        lines = []
        syntaxLines = []
        errorMessage = nil
        loadRevision += 1
        navigationRevision += 1
    }

    func loadIfNeeded(force: Bool = false) async {
        guard force || (content == nil && !isLoading) else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID {
                isLoading = false
                activeLoadID = nil
            }
        }
        do {
            let response: ProjectFileContentResponse
            switch scope {
            case .project(let id):
                response = try await apiClient.fetchProjectFileContent(projectId: id, path: reference.path)
            case .agent(let id):
                response = try await apiClient.fetchAgentFileContent(agentId: id, path: reference.path)
            case .session(let agentID, let sessionID):
                response = try await apiClient.fetchSessionLinkedFile(agentId: agentID, sessionId: sessionID, path: reference.path)
            case .unavailable:
                errorMessage = "Open this link from a conversation with a project or agent."
                return
            }
            // Keep decoding and line splitting off the UI actor, including large files.
            let prepared = await Task.detached(priority: .userInitiated) {
                if let data = response.imageData {
                    let source = CGImageSourceCreateWithData(data as CFData, nil)
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096,
                        kCGImageSourceShouldCacheImmediately: true,
                    ]
                    let image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
                    return (lines: [String](), image: image)
                }
                return (lines: response.content.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .components(separatedBy: "\n"), image: Optional<CGImage>.none)
            }.value
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            guard response.imageData == nil || prepared.image != nil else {
                errorMessage = "Unable to decode this image. The file may be damaged or its format unsupported."
                return
            }
            content = response
            lines = prepared.lines
            image = prepared.image
            // Tokenization runs off MainActor and is cached for lazy line rendering.
            syntaxLines = []
            if response.imageData == nil,
               let language = Self.syntaxLanguage(for: reference.path) {
                let normalized = prepared.lines.joined(separator: "\n")
                let tokens = await SyntaxHighlighting.tokens(code: normalized, language: language)
                let highlighted = await Task.detached(priority: .utility) { Self.splitSyntax(tokens) }.value
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                syntaxLines = highlighted
            }
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            errorMessage = "Unable to open this file. It may be unavailable, not linked in this conversation, or in an unsupported format. \(error.localizedDescription)"
        }
    }
    nonisolated static func syntaxLanguage(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": "swift"
        case "kt", "kts": "kotlin"
        case "js", "jsx": "javascript"
        case "ts", "tsx": "typescript"
        case "json": "json"
        case "py": "python"
        case "sh", "bash": "bash"
        case "c", "h": "c"
        case "cpp", "hpp", "cc": "cpp"
        case "rs": "rust"
        case "yaml", "yml": "yaml"
        case "md": "markdown"
        case "html", "xml": "markup"
        case "css": "css"
        default: nil
        }
    }

    nonisolated static func splitSyntax(_ tokens: [SyntaxHighlightToken]) -> [[SourceSyntaxRun]] {
        var lines: [[SourceSyntaxRun]] = [[]]
        for token in tokens {
            let parts = token.content.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append(.init(text: part, kind: token.kind)) }
            }
        }
        return lines
    }

}


struct SourceSyntaxRun: Sendable, Equatable {
    let text: String
    let kind: String
}
