import Foundation
import Protocols

enum PlanArtifactStorageKind {
    static let repository = "repository"
    static let workspace = "workspace"
}

struct PlanArtifactRequest: Sendable {
    var project: ProjectRecord
    var agentID: String
    var sessionID: String
    var sessionTitle: String
    var messageEventID: String
    var markdown: String
    var createdAt: Date
    var repositoryRootURL: URL?
    var workspaceProjectURL: URL
}

struct PlanArtifactService {
    var fileManager: FileManager = .default

    func createArtifact(_ request: PlanArtifactRequest) throws -> PlanArtifactRecord {
        let baseName = Self.planName(from: request.markdown, fallback: request.sessionTitle)
        let target = try targetDirectory(baseName: baseName, request: request)
        let planName = target.directoryURL.lastPathComponent
        let markdownURL = target.directoryURL.appendingPathComponent("\(planName).md", isDirectory: false)
        let manifestURL = target.directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
        let htmlURL = target.directoryURL.appendingPathComponent("index.html", isDirectory: false)
        let assetsURL = target.directoryURL.appendingPathComponent("assets", isDirectory: true)
        let styleURL = assetsURL.appendingPathComponent("style.css", isDirectory: false)
        let webPath = Self.webPath(projectID: request.project.id, planName: planName)

        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try normalizedMarkdown(request.markdown).write(to: markdownURL, atomically: true, encoding: .utf8)
        try Self.defaultCSS.write(to: styleURL, atomically: true, encoding: .utf8)
        try PlanMarkdownRenderer.htmlDocument(
            markdown: request.markdown,
            title: planName,
            stylesheetPath: "web/resource?path=assets/style.css"
        ).write(to: htmlURL, atomically: true, encoding: .utf8)

        let record = PlanArtifactRecord(
            projectId: request.project.id,
            projectName: request.project.name,
            agentId: request.agentID,
            sessionId: request.sessionID,
            messageEventId: request.messageEventID,
            planName: planName,
            createdAt: request.createdAt,
            storageKind: target.storageKind,
            markdownPath: markdownURL.path,
            webUrl: webPath
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (try encoder.encode(record) + Data("\n".utf8)).write(to: manifestURL, options: .atomic)
        return record
    }

    func loadArtifact(projectID: String, planName: String, repositoryRootURL: URL?, workspaceProjectURL: URL) -> PlanArtifactRecord? {
        guard let manifestURL = manifestURL(projectID: projectID, planName: planName, repositoryRootURL: repositoryRootURL, workspaceProjectURL: workspaceProjectURL) else {
            return nil
        }
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlanArtifactRecord.self, from: data)
    }

    func webFileURL(projectID: String, planName: String, resourcePath: String?, repositoryRootURL: URL?, workspaceProjectURL: URL) -> URL? {
        guard let directoryURL = artifactDirectoryURL(
            projectID: projectID,
            planName: planName,
            repositoryRootURL: repositoryRootURL,
            workspaceProjectURL: workspaceProjectURL
        ) else {
            return nil
        }
        let relativePath = resourcePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (relativePath?.isEmpty == false)
            ? directoryURL.appendingPathComponent(relativePath!, isDirectory: false).standardizedFileURL
            : directoryURL.appendingPathComponent("index.html", isDirectory: false).standardizedFileURL
        guard isURL(target, inside: directoryURL) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return target
    }

    func webFile(projectID: String, planName: String, resourcePath: String?, repositoryRootURL: URL?, workspaceProjectURL: URL) throws -> (data: Data, contentType: String)? {
        guard let directoryURL = artifactDirectoryURL(
            projectID: projectID,
            planName: planName,
            repositoryRootURL: repositoryRootURL,
            workspaceProjectURL: workspaceProjectURL
        ) else {
            return nil
        }

        let relativePath = resourcePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if relativePath?.isEmpty ?? true {
            let markdownURL = directoryURL.appendingPathComponent("\(planName).md", isDirectory: false)
            if let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) {
                let html = PlanMarkdownRenderer.htmlDocument(
                    markdown: markdown,
                    title: planName,
                    stylesheetPath: "web/resource?path=assets/style.css"
                )
                return (Data(html.utf8), Self.contentType(for: "html"))
            }
        }

        if relativePath == "assets/style.css" {
            return (Data(Self.defaultCSS.utf8), Self.contentType(for: "css"))
        }

        guard let url = webFileURL(
            projectID: projectID,
            planName: planName,
            resourcePath: resourcePath,
            repositoryRootURL: repositoryRootURL,
            workspaceProjectURL: workspaceProjectURL
        ) else {
            return nil
        }
        return (try Data(contentsOf: url), Self.contentType(for: url.pathExtension))
    }

    func manifestURL(projectID: String, planName: String, repositoryRootURL: URL?, workspaceProjectURL: URL) -> URL? {
        artifactDirectoryURL(
            projectID: projectID,
            planName: planName,
            repositoryRootURL: repositoryRootURL,
            workspaceProjectURL: workspaceProjectURL
        )?.appendingPathComponent("manifest.json", isDirectory: false)
    }

    func artifactDirectoryURL(projectID: String, planName: String, repositoryRootURL: URL?, workspaceProjectURL: URL) -> URL? {
        guard Self.isSafePlanName(planName) else {
            return nil
        }
        let candidates = artifactDirectoryCandidates(repositoryRootURL: repositoryRootURL, workspaceProjectURL: workspaceProjectURL)
            .map { $0.appendingPathComponent(planName, isDirectory: true).standardizedFileURL }
        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func targetDirectory(baseName: String, request: PlanArtifactRequest) throws -> (directoryURL: URL, storageKind: String) {
        let repositoryBase = request.repositoryRootURL?
            .appendingPathComponent(".sloppy", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
            .standardizedFileURL
        if let repositoryBase,
           let directoryURL = try? uniqueDirectory(baseURL: repositoryBase, baseName: baseName) {
            return (directoryURL, PlanArtifactStorageKind.repository)
        }

        let workspaceBase = request.workspaceProjectURL
            .appendingPathComponent("plans", isDirectory: true)
            .standardizedFileURL
        return (try uniqueDirectory(baseURL: workspaceBase, baseName: baseName), PlanArtifactStorageKind.workspace)
    }

    private func uniqueDirectory(baseURL: URL, baseName: String) throws -> URL {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        var candidate = baseURL.appendingPathComponent(baseName, isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
            return candidate
        }
        let stamp = Self.timestampSlug(Date())
        var index = 0
        while true {
            let suffix = index == 0 ? stamp : "\(stamp)-\(index)"
            candidate = baseURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
                return candidate
            }
            index += 1
        }
    }

    private func artifactDirectoryCandidates(repositoryRootURL: URL?, workspaceProjectURL: URL) -> [URL] {
        var candidates: [URL] = []
        if let repositoryRootURL {
            candidates.append(
                repositoryRootURL
                    .appendingPathComponent(".sloppy", isDirectory: true)
                    .appendingPathComponent("plans", isDirectory: true)
                    .standardizedFileURL
            )
        }
        candidates.append(workspaceProjectURL.appendingPathComponent("plans", isDirectory: true).standardizedFileURL)
        return candidates
    }

    private func normalizedMarkdown(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed + "\n"
    }

    private func isURL(_ child: URL, inside parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    static func planName(from markdown: String, fallback: String) -> String {
        if let heading = firstHeading(in: markdown) {
            return slug(heading)
        }
        return slug(fallback)
    }

    static func webPath(projectID: String, planName: String) -> String {
        "/v1/projects/\(urlPath(projectID))/plans/\(urlPath(planName))/web"
    }

    static func isSafePlanName(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[a-z0-9][a-z0-9-]{0,119}$"#, options: .regularExpression) != nil
    }

    static func contentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js", "mjs":
            return "application/javascript; charset=utf-8"
        case "json":
            return "application/json"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "md", "markdown":
            return "text/markdown; charset=utf-8"
        default:
            return "application/octet-stream"
        }
    }

    private static func firstHeading(in markdown: String) -> String? {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else {
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " else {
                continue
            }
            let title = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                return String(title)
            }
        }
        return nil
    }

    private static func slug(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let separated = folded.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let trimmed = separated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "plan" : String(trimmed.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func timestampSlug(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func urlPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static let defaultCSS =
        """
        :root {
          color-scheme: light;
          --page-bg: #f6f3ec;
          --paper: #fffdf8;
          --paper-soft: #f0ece2;
          --paper-strong: #e5ded1;
          --ink: #191612;
          --muted: #766f65;
          --faint: #aaa195;
          --line: #d8d0c2;
          --accent: #d76f51;
          --accent-soft: #fff1ea;
          --accent-strong: #b84f34;
          --success: #698a55;
          --warn: #ad7b2b;
          --danger: #c45c48;
          --diff-add-bg: rgba(105, 138, 85, 0.16);
          --diff-add-fg: #3f6f2a;
          --diff-delete-bg: rgba(196, 92, 72, 0.14);
          --diff-delete-fg: #a43d2b;
          --diff-hunk-bg: rgba(215, 111, 81, 0.12);
          --diff-hunk-fg: #9b4b31;
          --diff-meta-fg: #766f65;
          --code-symbol-fg: #9b4b31;
          --code-file-fg: #3f6f2a;
          --code-path-fg: #ad7b2b;
          --code-muted-fg: #766f65;
          --syntax-keyword-fg: #b84f34;
          --syntax-type-fg: #7b5fb2;
          --syntax-string-fg: #3f6f2a;
          --syntax-number-fg: #9b4b31;
          --syntax-comment-fg: #8f877a;
          --code-bg: #121311;
          --code-fg: #f4efe5;
          --shadow: 0 18px 60px rgba(54, 43, 30, 0.08);
          --mono: "Fira Code", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
          --serif: ui-serif, Georgia, "Times New Roman", serif;
          --sans: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            color-scheme: dark;
            --page-bg: #0b0b09;
            --paper: #11110f;
            --paper-soft: #181713;
            --paper-strong: #222018;
            --ink: #f3efe6;
            --muted: #b2aa9c;
            --faint: #777063;
            --line: #3a352b;
            --accent: #ccff00;
            --accent-soft: rgba(204, 255, 0, 0.08);
            --accent-strong: #e2ff62;
            --success: #00ffff;
            --warn: #ffcc00;
            --danger: #ff6b57;
            --diff-add-bg: rgba(0, 255, 255, 0.14);
            --diff-add-fg: #72fff4;
            --diff-delete-bg: rgba(255, 107, 87, 0.16);
            --diff-delete-fg: #ff9b8d;
            --diff-hunk-bg: rgba(204, 255, 0, 0.1);
            --diff-hunk-fg: #e2ff62;
            --diff-meta-fg: #b2aa9c;
            --code-symbol-fg: #e2ff62;
            --code-file-fg: #72fff4;
            --code-path-fg: #ffcc00;
            --code-muted-fg: #b2aa9c;
            --syntax-keyword-fg: #ffcc00;
            --syntax-type-fg: #72fff4;
            --syntax-string-fg: #b7ff7a;
            --syntax-number-fg: #ff9b8d;
            --syntax-comment-fg: #777063;
            --code-bg: #050605;
            --code-fg: #f4f4ee;
            --shadow: 0 24px 80px rgba(0, 0, 0, 0.35);
          }
        }

        * { box-sizing: border-box; }

        html {
          min-height: 100%;
          background:
            linear-gradient(90deg, rgba(215, 111, 81, 0.06) 1px, transparent 1px),
            linear-gradient(180deg, rgba(215, 111, 81, 0.05) 1px, transparent 1px),
            var(--page-bg);
          background-size: 44px 44px;
        }

        body {
          margin: 0;
          color: var(--ink);
          background: transparent;
          font: 15px/1.7 var(--sans);
          text-rendering: optimizeLegibility;
          -webkit-font-smoothing: antialiased;
        }

        body::before {
          content: "Sloppy / plan artifact";
          display: block;
          position: sticky;
          top: 0;
          z-index: 2;
          padding: 14px clamp(18px, 4vw, 56px);
          border-bottom: 1px solid var(--line);
          color: var(--muted);
          background: color-mix(in srgb, var(--page-bg) 86%, transparent);
          backdrop-filter: blur(12px);
          font: 11px/1 var(--mono);
          letter-spacing: 0.12em;
          text-transform: uppercase;
        }

        main {
          counter-reset: section;
          width: min(920px, calc(100vw - 32px));
          margin: 0 auto;
          padding: clamp(40px, 7vw, 88px) 0 96px;
        }

        h1, h2, h3, h4, h5, h6 {
          color: var(--ink);
          font-family: var(--serif);
          font-weight: 520;
          line-height: 1.2;
          letter-spacing: 0;
        }

        h1 {
          max-width: 760px;
          margin: 0 0 18px;
          font-size: clamp(2.25rem, 6vw, 4.6rem);
          line-height: 0.98;
        }

        h1::before {
          content: "Implementation plan";
          display: block;
          margin-bottom: 14px;
          color: var(--faint);
          font: 11px/1.4 var(--mono);
          letter-spacing: 0.14em;
          text-transform: uppercase;
        }

        h2 {
          counter-increment: section;
          display: flex;
          align-items: baseline;
          gap: 12px;
          margin: 56px 0 10px;
          padding-top: 28px;
          border-top: 1px solid var(--line);
          font-size: clamp(1.45rem, 3vw, 2.05rem);
        }

        h2::before {
          content: counter(section, decimal-leading-zero);
          flex: 0 0 auto;
          padding: 3px 7px;
          border-radius: 6px;
          color: var(--muted);
          background: var(--paper-strong);
          font: 11px/1 var(--mono);
        }

        h3 {
          margin: 30px 0 10px;
          font-size: 1.2rem;
        }

        h4, h5, h6 {
          margin: 24px 0 8px;
          font-family: var(--mono);
          font-size: 0.86rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
        }

        p {
          max-width: 780px;
          margin: 0 0 16px;
        }

        h1 + p {
          max-width: 760px;
          margin: 18px 0 36px;
          padding: 18px 20px;
          border: 1px solid var(--line);
          border-radius: 8px;
          color: var(--muted);
          background: color-mix(in srgb, var(--paper) 82%, var(--paper-soft));
          box-shadow: var(--shadow);
        }

        a {
          color: var(--accent-strong);
          text-decoration-thickness: 1px;
          text-underline-offset: 3px;
        }

        hr {
          height: 1px;
          margin: 36px 0;
          border: 0;
          background: var(--line);
        }

        ul, ol {
          max-width: 780px;
          margin: 12px 0 18px;
          padding-left: 0;
          list-style: none;
        }

        li {
          position: relative;
          margin: 8px 0;
          padding-left: 24px;
        }

        ul li::before {
          content: "";
          position: absolute;
          left: 4px;
          top: 0.78em;
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: var(--accent);
          transform: translateY(-50%);
        }

        ol {
          counter-reset: ordered-list;
        }

        ol li {
          counter-increment: ordered-list;
          padding-left: 36px;
        }

        ol li::before {
          content: counter(ordered-list, decimal-leading-zero);
          position: absolute;
          left: 0;
          top: 0.15em;
          color: var(--muted);
          font: 11px/1 var(--mono);
        }

        pre {
          max-width: 100%;
          margin: 18px 0 28px;
          overflow-x: auto;
          padding: 20px 22px;
          border: 1px solid color-mix(in srgb, var(--code-fg) 12%, transparent);
          border-radius: 8px;
          color: var(--code-fg);
          background: var(--code-bg);
          box-shadow: var(--shadow);
        }

        code {
          font-family: var(--mono);
          font-size: 0.92em;
        }

        :not(pre) > code {
          padding: 0.12em 0.36em;
          border: 1px solid var(--line);
          border-radius: 4px;
          color: color-mix(in srgb, var(--ink) 84%, var(--accent-strong));
          background: var(--paper-soft);
          white-space: nowrap;
        }

        h1 code,
        h2 code,
        h3 code {
          padding: 0;
          border: 0;
          border-radius: 0;
          color: var(--accent-strong);
          background: transparent;
          font-family: inherit;
          font-size: 0.94em;
          font-weight: inherit;
          white-space: normal;
        }

        pre code {
          display: block;
          min-width: max-content;
          font-size: 0.86rem;
          line-height: 1.65;
        }

        pre code.language-diff,
        pre code.language-patch {
          padding: 4px 0;
        }

        pre code.language-text,
        pre code.language-txt,
        pre code.language-plain {
          padding: 4px 0;
        }

        .plan-code-line {
          display: block;
          margin: 0 -22px;
          padding: 0 22px;
          white-space: pre;
        }

        pre code:is(
          .language-js,
          .language-jsx,
          .language-javascript,
          .language-ts,
          .language-tsx,
          .language-typescript,
          .language-swift
        ) {
          counter-reset: code-line;
          padding: 4px 0;
        }

        pre code:is(
          .language-js,
          .language-jsx,
          .language-javascript,
          .language-ts,
          .language-tsx,
          .language-typescript,
          .language-swift
        ) .plan-code-line {
          counter-increment: code-line;
          padding-left: 0;
        }

        pre code:is(
          .language-js,
          .language-jsx,
          .language-javascript,
          .language-ts,
          .language-tsx,
          .language-typescript,
          .language-swift
        ) .plan-code-line::before {
          content: counter(code-line);
          display: inline-block;
          width: 4ch;
          margin-right: 16px;
          padding-right: 12px;
          border-right: 1px solid color-mix(in srgb, var(--code-fg) 12%, transparent);
          color: var(--code-muted-fg);
          text-align: right;
          user-select: none;
        }

        .plan-code-symbol {
          color: var(--code-symbol-fg);
          font-weight: 650;
        }

        .plan-code-file {
          color: var(--code-file-fg);
        }

        .plan-code-path {
          color: var(--code-path-fg);
        }

        .plan-code-muted {
          color: var(--code-muted-fg);
        }

        .syntax-keyword {
          color: var(--syntax-keyword-fg);
          font-weight: 650;
        }

        .syntax-type {
          color: var(--syntax-type-fg);
        }

        .syntax-string {
          color: var(--syntax-string-fg);
        }

        .syntax-number {
          color: var(--syntax-number-fg);
        }

        .syntax-comment {
          color: var(--syntax-comment-fg);
          font-style: italic;
        }

        .diff-line {
          display: block;
          margin: 0 -22px;
          padding: 0 22px;
          white-space: pre;
        }

        .diff-line-add {
          color: var(--diff-add-fg);
          background: var(--diff-add-bg);
        }

        .diff-line-delete {
          color: var(--diff-delete-fg);
          background: var(--diff-delete-bg);
        }

        .diff-line-hunk {
          color: var(--diff-hunk-fg);
          background: var(--diff-hunk-bg);
        }

        .diff-line-meta,
        .diff-line-file,
        .diff-line-note {
          color: var(--diff-meta-fg);
        }

        .diff-line-meta,
        .diff-line-file {
          font-weight: 650;
        }

        blockquote {
          max-width: 780px;
          margin: 22px 0;
          padding: 16px 18px 16px 20px;
          border: 1px solid var(--line);
          border-left: 4px solid var(--accent);
          border-radius: 8px;
          color: var(--muted);
          background: var(--accent-soft);
        }

        blockquote p:last-child {
          margin-bottom: 0;
        }

        table {
          width: 100%;
          margin: 18px 0 30px;
          overflow: hidden;
          border: 1px solid var(--line);
          border-spacing: 0;
          border-radius: 8px;
          background: var(--paper);
          box-shadow: var(--shadow);
        }

        th, td {
          border-bottom: 1px solid var(--line);
          border-right: 1px solid var(--line);
          padding: 12px 14px;
          vertical-align: top;
        }

        tr:last-child td {
          border-bottom: 0;
        }

        th:last-child,
        td:last-child {
          border-right: 0;
        }

        th {
          text-align: left;
          color: var(--muted);
          background: var(--paper-soft);
          font: 11px/1.3 var(--mono);
          letter-spacing: 0.08em;
          text-transform: uppercase;
        }

        img, video {
          max-width: 100%;
          height: auto;
          border: 1px solid var(--line);
          border-radius: 8px;
        }

        .plan-page > section,
        .plan-page > div {
          max-width: 100%;
        }

        @media (max-width: 720px) {
          body::before {
            padding-inline: 18px;
          }

          main {
            width: min(100% - 28px, 920px);
            padding-top: 36px;
          }

          h2 {
            align-items: flex-start;
            flex-direction: column;
            gap: 8px;
          }

          h1 + p,
          pre,
          table {
            box-shadow: none;
          }
        }
        """
}

enum PlanMarkdownRenderer {
    static func htmlDocument(markdown: String, title: String, stylesheetPath: String) -> String {
        let body = render(markdown)
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <link rel="stylesheet" href="assets/style.css">
          <link rel="stylesheet" href="\(escapeAttribute(stylesheetPath))">
        </head>
        <body>
          <main class="plan-page">
        \(body)
          </main>
        </body>
        </html>
        """
    }

    static func render(_ markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var orderedListItems: [String] = []
        var inCode = false
        var codeLanguage = ""
        var codeLines: [String] = []
        var tableRows: [[String]] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(paragraph.map(inlineHTML).joined(separator: " "))</p>")
            paragraph.removeAll()
        }
        func flushList() {
            guard !listItems.isEmpty else { return }
            html.append("<ul>\n\(listItems.map { "<li>\($0)</li>" }.joined(separator: "\n"))\n</ul>")
            listItems.removeAll()
        }
        func flushOrderedList() {
            guard !orderedListItems.isEmpty else { return }
            html.append("<ol>\n\(orderedListItems.map { "<li>\($0)</li>" }.joined(separator: "\n"))\n</ol>")
            orderedListItems.removeAll()
        }
        func flushTable() {
            guard !tableRows.isEmpty else { return }
            let rows = tableRows.enumerated().map { index, cells in
                let tag = index == 0 ? "th" : "td"
                return "<tr>\(cells.map { "<\(tag)>\(inlineHTML($0.trimmingCharacters(in: .whitespaces)))</\(tag)>" }.joined())</tr>"
            }.joined(separator: "\n")
            html.append("<table>\n\(rows)\n</table>")
            tableRows.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    html.append(codeBlockHTML(language: codeLanguage, lines: codeLines))
                    codeLines.removeAll()
                    codeLanguage = ""
                    inCode = false
                } else {
                    flushParagraph()
                    flushList()
                    flushOrderedList()
                    flushTable()
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushTable()
                continue
            }
            if line.hasPrefix("<") {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushTable()
                html.append(sanitizeRawHTML(rawLine))
                continue
            }
            if isHorizontalRule(line) {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushTable()
                html.append("<hr>")
                continue
            }
            if let heading = headingHTML(line) {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushTable()
                html.append(heading)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                flushList()
                flushOrderedList()
                flushTable()
                let text = line.drop { $0 == ">" || $0 == " " }
                html.append("<blockquote>\(inlineHTML(String(text)))</blockquote>")
                continue
            }
            if let item = unorderedListItem(line) {
                flushParagraph()
                flushOrderedList()
                flushTable()
                listItems.append(inlineHTML(item))
                continue
            }
            if let item = orderedListItem(line) {
                flushParagraph()
                flushList()
                flushTable()
                orderedListItems.append(inlineHTML(item))
                continue
            }
            if isTableRow(line) {
                flushParagraph()
                flushList()
                flushOrderedList()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|")
                if !cells.allSatisfy({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "-: ")).isEmpty }) {
                    tableRows.append(cells)
                }
                continue
            }
            flushList()
            flushOrderedList()
            flushTable()
            paragraph.append(rawLine.trimmingCharacters(in: .whitespaces))
        }
        if inCode {
            html.append(codeBlockHTML(language: codeLanguage, lines: codeLines))
        }
        flushParagraph()
        flushList()
        flushOrderedList()
        flushTable()
        return html.map { "    \($0)" }.joined(separator: "\n")
    }

    private static func headingHTML(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return "<h\(level)>\(inlineHTML(String(text)))</h\(level)>"
    }

    private static func unorderedListItem(_ line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedListItem(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: "."),
              line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)] == " "
        else {
            return nil
        }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else {
            return nil
        }
        return String(line[line.index(dotIndex, offsetBy: 2)...])
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "-" }
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && line.split(separator: "|").count >= 2
    }

    private static func inlineHTML(_ text: String) -> String {
        var value = sanitizeRawHTML(escapeHTMLPreservingSafeTags(text))
        value = value.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "<em>$1</em>", options: .regularExpression)
        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)\s]+)\)"#,
            with: { match in
                let label = escapeHTML(match[1])
                let href = safeURL(match[2])
                return href.map { "<a href=\"\(escapeAttribute($0))\">\(label)</a>" } ?? label
            }
        )
        return value
    }

    private static func codeBlockHTML(language: String, lines: [String]) -> String {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let languageAttribute = normalizedLanguage.isEmpty
            ? ""
            : " class=\"language-\(escapeAttribute(normalizedLanguage))\""
        let body: String
        if isDiffLanguage(normalizedLanguage) {
            body = lines.map(diffLineHTML).joined()
        } else if isPlainTextListLanguage(normalizedLanguage) {
            body = lines.map(plainTextLineHTML).joined()
        } else if isSyntaxLanguage(normalizedLanguage) {
            body = lines.map { syntaxLineHTML($0, language: normalizedLanguage) }.joined()
        } else {
            body = escapeHTML(lines.joined(separator: "\n"))
        }
        return "<pre><code\(languageAttribute)>\(body)</code></pre>"
    }

    private static func isDiffLanguage(_ language: String) -> Bool {
        language == "diff" || language == "patch"
    }

    private static func isPlainTextListLanguage(_ language: String) -> Bool {
        language == "text" || language == "txt" || language == "plain"
    }

    private static func isSyntaxLanguage(_ language: String) -> Bool {
        [
            "js",
            "jsx",
            "javascript",
            "ts",
            "tsx",
            "typescript",
            "swift"
        ].contains(language)
    }

    private static func plainTextLineHTML(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let className: String
        if trimmed.isEmpty {
            className = "plan-code-line plan-code-muted"
        } else if looksLikePathReference(trimmed) {
            className = "plan-code-line plan-code-path"
        } else if looksLikeFileReference(trimmed) {
            className = "plan-code-line plan-code-file"
        } else if looksLikeSymbolReference(trimmed) {
            className = "plan-code-line plan-code-symbol"
        } else {
            className = "plan-code-line"
        }
        return "<span class=\"\(className)\">\(escapeHTML(line))</span>"
    }

    private static func syntaxLineHTML(_ line: String, language: String) -> String {
        "<span class=\"plan-code-line\">\(syntaxHTML(line, language: language))</span>"
    }

    private static func syntaxHTML(_ line: String, language: String) -> String {
        let isTypeScriptFamily = ["js", "jsx", "javascript", "ts", "tsx", "typescript"].contains(language)
        let keywords = language == "swift" ? swiftKeywords : typeScriptKeywords
        let builtInTypes = language == "swift" ? swiftBuiltInTypes : typeScriptBuiltInTypes
        var html = ""
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "/", let next = line.index(index, offsetBy: 1, limitedBy: line.endIndex), next < line.endIndex, line[next] == "/" {
                html += "<span class=\"syntax-comment\">\(escapeHTML(String(line[index...])))</span>"
                break
            }

            if character == "\"" || (isTypeScriptFamily && (character == "'" || character == "`")) {
                let start = index
                let delimiter = character
                index = line.index(after: index)
                var isEscaped = false
                while index < line.endIndex {
                    let current = line[index]
                    index = line.index(after: index)
                    if isEscaped {
                        isEscaped = false
                        continue
                    }
                    if current == "\\" {
                        isEscaped = true
                        continue
                    }
                    if current == delimiter {
                        break
                    }
                }
                html += "<span class=\"syntax-string\">\(escapeHTML(String(line[start..<index])))</span>"
                continue
            }

            if character.isNumber {
                let start = index
                index = line.index(after: index)
                while index < line.endIndex {
                    let current = line[index]
                    if current.isNumber || current == "." || current == "_" {
                        index = line.index(after: index)
                    } else {
                        break
                    }
                }
                html += "<span class=\"syntax-number\">\(escapeHTML(String(line[start..<index])))</span>"
                continue
            }

            if isIdentifierStart(character) {
                let start = index
                index = line.index(after: index)
                while index < line.endIndex, isIdentifierPart(line[index]) {
                    index = line.index(after: index)
                }
                let word = String(line[start..<index])
                if keywords.contains(word) {
                    html += "<span class=\"syntax-keyword\">\(escapeHTML(word))</span>"
                } else if builtInTypes.contains(word) || looksLikeTypeIdentifier(word) {
                    html += "<span class=\"syntax-type\">\(escapeHTML(word))</span>"
                } else {
                    html += escapeHTML(word)
                }
                continue
            }

            html += escapeHTML(String(character))
            index = line.index(after: index)
        }

        return html
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private static func isIdentifierPart(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func looksLikeTypeIdentifier(_ value: String) -> Bool {
        guard let first = value.first else {
            return false
        }
        return first.isUppercase
    }

    private static let typeScriptKeywords: Set<String> = [
        "as",
        "async",
        "await",
        "break",
        "case",
        "catch",
        "class",
        "const",
        "continue",
        "default",
        "delete",
        "else",
        "enum",
        "export",
        "extends",
        "false",
        "finally",
        "for",
        "from",
        "function",
        "if",
        "implements",
        "import",
        "in",
        "interface",
        "let",
        "new",
        "null",
        "private",
        "protected",
        "public",
        "readonly",
        "return",
        "switch",
        "this",
        "throw",
        "true",
        "try",
        "type",
        "undefined",
        "var",
        "while"
    ]

    private static let typeScriptBuiltInTypes: Set<String> = [
        "Array",
        "Promise",
        "Record",
        "any",
        "boolean",
        "never",
        "number",
        "object",
        "string",
        "unknown",
        "void"
    ]

    private static let swiftKeywords: Set<String> = [
        "actor",
        "as",
        "async",
        "await",
        "case",
        "catch",
        "class",
        "continue",
        "default",
        "defer",
        "else",
        "enum",
        "extension",
        "false",
        "for",
        "func",
        "guard",
        "if",
        "import",
        "in",
        "internal",
        "let",
        "nil",
        "private",
        "protocol",
        "public",
        "return",
        "self",
        "static",
        "struct",
        "switch",
        "throw",
        "throws",
        "true",
        "try",
        "var",
        "while"
    ]

    private static let swiftBuiltInTypes: Set<String> = [
        "Array",
        "Bool",
        "Data",
        "Date",
        "Dictionary",
        "Double",
        "Float",
        "Int",
        "Optional",
        "Result",
        "Set",
        "String",
        "URL",
        "UUID",
        "Void"
    ]

    private static func looksLikePathReference(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace) else {
            return false
        }
        return value.hasSuffix("/") || value.contains("/")
    }

    private static func looksLikeFileReference(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace),
              let dotIndex = value.lastIndex(of: "."),
              dotIndex > value.startIndex
        else {
            return false
        }
        let extensionStart = value.index(after: dotIndex)
        guard extensionStart < value.endIndex else {
            return false
        }
        let ext = value[extensionStart...]
        return ext.count <= 10 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func looksLikeSymbolReference(_ value: String) -> Bool {
        guard let first = value.first,
              first.isUppercase,
              !value.contains(where: \.isWhitespace),
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else {
            return false
        }
        return value.contains { $0.isLowercase }
    }

    private static func diffLineHTML(_ line: String) -> String {
        let className: String
        if line.hasPrefix("@@") {
            className = "diff-line diff-line-hunk"
        } else if line.hasPrefix("+++") || line.hasPrefix("---") {
            className = "diff-line diff-line-file"
        } else if line.hasPrefix("+") {
            className = "diff-line diff-line-add"
        } else if line.hasPrefix("-") {
            className = "diff-line diff-line-delete"
        } else if isDiffMetadataLine(line) {
            className = "diff-line diff-line-meta"
        } else if line.hasPrefix("\\") {
            className = "diff-line diff-line-note"
        } else {
            className = "diff-line"
        }
        return "<span class=\"\(className)\">\(escapeHTML(line))</span>"
    }

    private static func isDiffMetadataLine(_ line: String) -> Bool {
        let prefixes = [
            "diff --git ",
            "index ",
            "new file mode ",
            "deleted file mode ",
            "old mode ",
            "new mode ",
            "similarity index ",
            "dissimilarity index ",
            "rename from ",
            "rename to "
        ]
        return prefixes.contains { line.hasPrefix($0) }
    }

    private static func sanitizeRawHTML(_ html: String) -> String {
        var value = html.replacingOccurrences(of: #"(?is)<\s*script[^>]*>.*?<\s*/\s*script\s*>"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(href|src)\s*=\s*("|')\s*javascript:[^"']*\2"#, with: "$1=\"#\"", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)<\s*(iframe|object|embed)[^>]*>.*?<\s*/\s*\1\s*>"#, with: "", options: .regularExpression)
        return value
    }

    private static func escapeHTMLPreservingSafeTags(_ text: String) -> String {
        // Raw HTML lines are handled separately; inline text is escaped to keep the generated page safe.
        escapeHTML(text)
    }

    private static func safeURL(_ raw: String) -> String? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("data:") {
            return nil
        }
        return raw
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension String {
    func replacingOccurrences(
        of pattern: String,
        with replacement: (RegexMatch) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let ns = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length))
        var result = self
        for match in matches.reversed() {
            var captures: [String] = []
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                captures.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement(RegexMatch(values: captures)))
        }
        return result
    }
}

private struct RegexMatch {
    let values: [String]

    subscript(index: Int) -> String {
        values.indices.contains(index) ? values[index] : ""
    }
}
