import Foundation

struct WidgetArtifactService {
    struct Size: Sendable, Equatable {
        let name: String
        let width: Int
        let height: Int
    }

    private struct Manifest: Codable {
        let id: String
        let kind: String
        let size: String
        let width: Int
        let height: Int
        let entry: String
        let mediaType: String
        let bundlePath: String
        let prompt: String
    }

    enum WidgetError: Error, Equatable {
        case invalidSize
        case invalidPrompt
        case invalidHTML
        case externalResource
    }

    static let entryFileName = "index.html"
    static let manifestFileName = "manifest.json"

    static func size(named value: String) throws -> Size {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "small":
            return Size(name: "small", width: 160, height: 120)
        case "medium":
            return Size(name: "medium", width: 320, height: 180)
        case "large":
            return Size(name: "large", width: 320, height: 320)
        default:
            throw WidgetError.invalidSize
        }
    }

    static func sizeName(width: Int, height: Int) -> String {
        if width == 320 && height == 180 {
            return "medium"
        }
        if width == 320 && height == 320 {
            return "large"
        }
        return "small"
    }

    static func normalizedPrompt(_ prompt: String) throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WidgetError.invalidPrompt
        }
        return trimmed
    }

    static func fallbackHTML(prompt: String, size: Size) throws -> String {
        let trimmed = try normalizedPrompt(prompt)
        let escaped = trimmed
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { width: \(size.width)px; height: \(size.height)px; margin: 0; overflow: hidden; background: #202124; color: #f5f5f5; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            body { display: grid; place-items: center; padding: 12px; box-sizing: border-box; }
            main { width: 100%; }
            strong { display: block; font-size: 15px; margin-bottom: 6px; }
            p { margin: 0; color: #b7b7b7; line-height: 1.35; }
          </style>
        </head>
        <body><main><strong>Widget draft</strong><p>\(escaped)</p></main></body>
        </html>
        """
    }

    static func validate(html: String) throws {
        let lowercased = html.lowercased()
        guard lowercased.contains("<!doctype html>") || lowercased.contains("<html") else {
            throw WidgetError.invalidHTML
        }
        let forbiddenPatterns = [
            #"\s(?:src|href|poster|data|action)\s*=\s*["']\s*(?:https?:|//)"#,
            #"@import\s+(?:url\()?["']?\s*(?:https?:|//)"#,
            #"url\(\s*["']?\s*(?:https?:|//)"#,
            #"\b(?:fetch|xmlhttprequest|websocket|eventsource|beacon|sendbeacon|importscripts)\s*\("#,
            #"<\s*(?:script|link)\b[^>]*\s(?:src|href)\s*="#
        ]
        for pattern in forbiddenPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                throw WidgetError.externalResource
            }
        }
    }

    static func bundlePath(id: String) -> String {
        ".sloppy/artifacts/widgets/\(id)/"
    }

    static func bundleDirectoryURL(id: String, currentRootURL: URL) -> URL {
        currentRootURL
            .appendingPathComponent(CoreConfig.defaultWorkspaceName, isDirectory: true)
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("widgets", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func writeBundle(
        id: String,
        prompt: String,
        html: String,
        size: Size,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try validate(html: html)

        let directoryURL = bundleDirectoryURL(id: id, currentRootURL: currentRootURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(html.utf8).write(
            to: directoryURL.appendingPathComponent(entryFileName, isDirectory: false),
            options: .atomic
        )

        let manifest = Manifest(
            id: id,
            kind: "widget",
            size: size.name,
            width: size.width,
            height: size.height,
            entry: entryFileName,
            mediaType: "text/html",
            bundlePath: bundlePath(id: id),
            prompt: prompt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(manifest)
        try payload.write(
            to: directoryURL.appendingPathComponent(manifestFileName, isDirectory: false),
            options: .atomic
        )
    }

    static func updateBundleHTML(
        id: String,
        html: String,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try validate(html: html)

        let directoryURL = bundleDirectoryURL(id: id, currentRootURL: currentRootURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(html.utf8).write(
            to: directoryURL.appendingPathComponent(entryFileName, isDirectory: false),
            options: .atomic
        )
    }
}
