# ADR 0012: View Markdown and HTML documents

- Date: 2026-11-17
- Status: local implementation; build and runtime verification blocked by disk space

## Context

ClientNative's conversation file-reference panel displays every text file as numbered source. Markdown and HTML documents should open as readable documents, with the original read-only source still available.

## Decision

Recognize md/markdown/mdown and html/htm case-insensitively. Default to Preview; retain the selected Preview/Raw mode in each file-tab view model across reloads. Explicit line references default or navigate to Raw to preserve source-line navigation. Other source files and images retain existing behavior. Mode switching never writes files or repeats the API fetch.

Reuse MarkdownDocumentView for Markdown. Render HTML in a separate ephemeral WKWebView, not the Browse runtime. Disable content JavaScript; prepend a restrictive CSP before untrusted markup. Allow inline CSS, data images and data fonts only. Deny frames, objects, forms, base URLs and remote/local resources. Deny navigation except about:blank and its anchors; only explicitly clicked http(s) links may open through SwiftUI openURL. No file base URL, cookies shared with Browse, message handlers or agent bridge.

## Consequences

HTML is a static document preview, not an executable web application. External CSS, scripts, relative resources and remote images do not load. Inline HTML styling remains available. Existing Core file access boundaries and API contracts do not change. Markdown uses the existing shared renderer and its existing resource policy.

## Verification

Added WorkspaceDocumentPreviewTests for defaults/extensions, mode/reload/source preservation and line navigation, plus HTML policy checks. Added opt-in WorkspaceDocumentRenderingTests to exercise the actual segmented control, Markdown/HTML rendering, source preservation and HTML script disabling.

2026-11-17: Swift parser accepts the five changed/new Swift files; diff whitespace check passes. XcodeBuildMCP SwiftPM tests failed during dependency/feature compilation with `No space left on device` before executing tests. Concurrent packaged macOS build was stopped. UI tests and screenshots remain pending; no deployment or commit.
