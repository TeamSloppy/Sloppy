import Foundation
import Testing
@testable import sloppy
@testable import Protocols

private func testProject(id: String = "plan-test", repoPath: String? = nil) -> ProjectRecord {
    ProjectRecord(
        id: id,
        name: "Plan Test",
        description: "Plan artifact tests",
        channels: [],
        tasks: [],
        repoPath: repoPath
    )
}

@Test
func planArtifactServiceWritesRepositoryLocalArtifactAndHandlesCollisions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("plan-artifact-\(UUID().uuidString)", isDirectory: true)
    let repo = root.appendingPathComponent("repo", isDirectory: true)
    let workspaceProject = root.appendingPathComponent("workspace-project", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspaceProject, withIntermediateDirectories: true)

    let service = PlanArtifactService()
    let request = PlanArtifactRequest(
        project: testProject(repoPath: repo.path),
        agentID: "agent",
        sessionID: "session",
        sessionTitle: "Fallback Title",
        messageEventID: "message-1",
        markdown: "# Implementation Plan\n\n- Build it\n",
        createdAt: Date(timeIntervalSince1970: 10),
        repositoryRootURL: repo,
        workspaceProjectURL: workspaceProject
    )

    let first = try service.createArtifact(request)
    let second = try service.createArtifact(request)

    #expect(first.storageKind == PlanArtifactStorageKind.repository)
    #expect(first.planName == "implementation-plan")
    #expect(second.planName != first.planName)
    let markdownURL = repo.appendingPathComponent(".sloppy/plans/\(first.planName)/\(first.planName).md")
    let manifestURL = repo.appendingPathComponent(".sloppy/plans/\(first.planName)/manifest.json")
    #expect(FileManager.default.fileExists(atPath: markdownURL.path))
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".sloppy/plans/\(first.planName)/index.html").path))
    #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".sloppy/plans/\(first.planName)/assets/style.css").path))

    let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
    #expect(markdown == "# Implementation Plan\n\n- Build it\n")
    let html = try String(contentsOf: repo.appendingPathComponent(".sloppy/plans/\(first.planName)/index.html"), encoding: .utf8)
    #expect(html.contains(#"href="assets/style.css""#))
    #expect(html.contains(#"href="web/resource?path=assets/style.css""#))
    let css = try String(contentsOf: repo.appendingPathComponent(".sloppy/plans/\(first.planName)/assets/style.css"), encoding: .utf8)
    #expect(css.contains("Sloppy / plan artifact"))
    #expect(css.contains("--accent: #d76f51"))
    #expect(css.contains(".diff-line-add"))
    #expect(css.contains(".plan-code-symbol"))
    #expect(css.contains(".syntax-keyword"))
    #expect(css.contains("h1 code"))
    #expect(css.contains("counter-reset: code-line"))
    #expect(css.contains(".plan-code-line::before"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(PlanArtifactRecord.self, from: Data(contentsOf: manifestURL))
    #expect(manifest == first)
}

@Test
func planArtifactServiceFallsBackToWorkspaceProjectPlans() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("plan-artifact-fallback-\(UUID().uuidString)", isDirectory: true)
    let workspaceProject = root.appendingPathComponent("workspace-project", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: workspaceProject, withIntermediateDirectories: true)

    let service = PlanArtifactService()
    let record = try service.createArtifact(
        PlanArtifactRequest(
            project: testProject(id: "fallback"),
            agentID: "agent",
            sessionID: "session",
            sessionTitle: "Fallback Plan",
            messageEventID: "message-1",
            markdown: "No heading body",
            createdAt: Date(timeIntervalSince1970: 20),
            repositoryRootURL: nil,
            workspaceProjectURL: workspaceProject
        )
    )

    #expect(record.storageKind == PlanArtifactStorageKind.workspace)
    #expect(record.planName == "fallback-plan")
    #expect(FileManager.default.fileExists(atPath: workspaceProject.appendingPathComponent("plans/\(record.planName)/manifest.json").path))
}

@Test
func planArtifactServiceDerivesSafePlanNames() {
    #expect(PlanArtifactService.planName(from: "Intro\n## Déjà Vu: Plan!!!\nBody", fallback: "Ignored") == "deja-vu-plan")
    #expect(PlanArtifactService.planName(from: "No heading", fallback: "Fallback Title") == "fallback-title")
    #expect(PlanArtifactService.planName(from: "No heading", fallback: "!!!") == "plan")
    #expect(PlanArtifactService.isSafePlanName("feature-plan-123"))
    #expect(!PlanArtifactService.isSafePlanName("../feature-plan"))
    #expect(!PlanArtifactService.isSafePlanName("Feature Plan"))
}

@Test
func planMarkdownRendererStripsUnsafeHTML() {
    let html = PlanMarkdownRenderer.render(
        """
        # Safe
        <section id="ok" onclick="bad()"><script>alert(1)</script>Body</section>
        [bad](javascript:alert(1))
        """
    )

    #expect(html.contains("<section id=\"ok\">Body</section>"))
    #expect(!html.contains("onclick"))
    #expect(!html.contains("<script"))
    #expect(!html.contains("javascript:"))
}

@Test
func planMarkdownRendererSupportsPlanDocumentBasics() {
    let html = PlanMarkdownRenderer.render(
        """
        # Plan

        ---

        1. First step
        2. Second step
        """
    )

    #expect(html.contains("<hr>"))
    #expect(html.contains("<ol>"))
    #expect(html.contains("<li>First step</li>"))
    #expect(html.contains("<li>Second step</li>"))
}

@Test
func planMarkdownRendererHighlightsDiffFences() {
    let html = PlanMarkdownRenderer.render(
        """
        ```diff
        diff --git a/App.swift b/App.swift
        --- a/App.swift
        +++ b/App.swift
        @@ -1,2 +1,3 @@
         import Foundation
        -let title = "Old"
        +let title = "New"
        ```
        """
    )

    #expect(html.contains(#"<code class="language-diff">"#))
    #expect(html.contains(#"<span class="diff-line diff-line-meta">diff --git a/App.swift b/App.swift</span>"#))
    #expect(html.contains(#"<span class="diff-line diff-line-file">--- a/App.swift</span>"#))
    #expect(html.contains(#"<span class="diff-line diff-line-hunk">@@ -1,2 +1,3 @@</span>"#))
    #expect(html.contains(#"<span class="diff-line diff-line-delete">-let title = "Old"</span>"#))
    #expect(html.contains(#"<span class="diff-line diff-line-add">+let title = "New"</span>"#))
}

@Test
func planMarkdownRendererHighlightsTextReferenceFences() {
    let html = PlanMarkdownRenderer.render(
        """
        ```text
        AppsView
        Sources/Apps/
        DiffViewer.swift
        DiffViewer.tsx
        run output
        ```
        """
    )

    #expect(html.contains(#"<code class="language-text">"#))
    #expect(html.contains(#"<span class="plan-code-line plan-code-symbol">AppsView</span>"#))
    #expect(html.contains(#"<span class="plan-code-line plan-code-path">Sources/Apps/</span>"#))
    #expect(html.contains(#"<span class="plan-code-line plan-code-file">DiffViewer.swift</span>"#))
    #expect(html.contains(#"<span class="plan-code-line plan-code-file">DiffViewer.tsx</span>"#))
    #expect(html.contains(#"<span class="plan-code-line">run output</span>"#))
}

@Test
func planMarkdownRendererHighlightsSyntaxFences() {
    let html = PlanMarkdownRenderer.render(
        """
        ```ts
        type DiffLineType = "add" | "delete"
        type ParsedDiffLine = {
          type: DiffLineType
          content: string
          oldLineNumber?: number
        }
        ```

        ```swift
        enum DiffLineType {
            case add
            let content: String
        }
        ```
        """
    )

    #expect(html.contains(#"<code class="language-ts">"#))
    #expect(html.contains(#"<span class="syntax-keyword">type</span> <span class="syntax-type">DiffLineType</span>"#))
    #expect(html.contains(#"<span class="syntax-string">"add"</span>"#))
    #expect(html.contains(#"content: <span class="syntax-type">string</span>"#))
    #expect(html.contains(#"oldLineNumber?: <span class="syntax-type">number</span>"#))
    #expect(html.contains(#"<code class="language-swift">"#))
    #expect(html.contains(#"<span class="syntax-keyword">enum</span> <span class="syntax-type">DiffLineType</span>"#))
    #expect(html.contains(#"<span class="syntax-keyword">case</span> add"#))
    #expect(html.contains(#"content: <span class="syntax-type">String</span>"#))
}

@Test
func planArtifactRoutesServeManifestWebAndRejectTraversal() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let projectID = "plan-route-\(UUID().uuidString.prefix(8).lowercased())"
    _ = try await service.createProject(ProjectCreateRequest(id: projectID, name: "Route Plan"))
    let event = try await service.recordPlanArtifact(
        agentID: "agent",
        sessionID: "session",
        sessionTitle: "Route Plan",
        projectID: projectID,
        messageEventID: "message-1",
        markdown: "# Route Plan\n\n```diff\n--- a/App.swift\n+++ b/App.swift\n@@ -1 +1 @@\n-old\n+new\n```\n\n```text\nAppsView\nDiffViewer.swift\n```\n",
        createdAt: Date(timeIntervalSince1970: 30)
    )

    let planName = event.artifact.planName
    let manifest = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/plans/\(planName)", body: nil)
    #expect(manifest.status == 200)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(PlanArtifactRecord.self, from: manifest.body)
    #expect(decoded.planName == planName)

    let web = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/plans/\(planName)/web", body: nil)
    #expect(web.status == 200)
    #expect(web.contentType == "text/html; charset=utf-8")
    #expect(String(data: web.body, encoding: .utf8)?.contains("Route Plan") == true)
    #expect(String(data: web.body, encoding: .utf8)?.contains(#"diff-line diff-line-add"#) == true)
    #expect(String(data: web.body, encoding: .utf8)?.contains(#"plan-code-line plan-code-symbol"#) == true)

    let css = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/plans/\(planName)/web/resource?path=assets/style.css", body: nil)
    #expect(css.status == 200)
    #expect(css.contentType == "text/css; charset=utf-8")
    #expect(String(data: css.body, encoding: .utf8)?.contains(".diff-line-add") == true)

    let traversal = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/plans/\(planName)/web/resource?path=../manifest.json", body: nil)
    #expect(traversal.status == 404)
}
