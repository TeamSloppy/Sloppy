# ADR 0010: Preview workspace images without a size cutoff

- Status: accepted for local implementation; deployment unverified
- Date: 2026-11-12

## Context

The file-content endpoints rejected files over 2 MiB and required UTF-8. JPEG screenshots therefore failed regardless of size, while ClientNative showed one misleading error for all failures. Large content preparation must not block the UI actor.

## Decision

Remove the 2 MiB rejection in project and agent file reads. Preserve project roots, the agent top-level allowlist and regular-file checks; resolve symlinks for agent boundary checks. Reject unsupported binary data.

Extend ProjectFileContentResponse in Core and ClientNative with optional imageData: Data? (Codable base64) and mediaType: String?, default nil. Existing text payloads remain compatible. Recognize PNG, JPEG, GIF, WebP, TIFF, BMP and HEIC by signature rather than filename. Image responses have empty content. ClientNative validates actual decoding through ImageIO.

Track loading through network fetch and background content preparation, including retry and refresh. Decode images and split lines outside MainActor. Use an orientation-aware first-frame preview downsampled to a maximum dimension of 4096 pixels to bound decoded raster memory, not accepted file size. Keep navigation and reload revisions separate. Use request identities to reject superseded responses.

## Consequences

Both Core and ClientNative need updating. Old Core still rejects images/large files; old clients ignore image fields and cannot render them. Legacy file editors are not converted into image viewers; the new image surface is the conversation file-reference panel.

This is still a whole-response JSON API, not an unlimited-memory streaming viewer. Base64 adds overhead; independent transport/proxy limits remain. Extremely large files still consume memory. Authenticated streaming and range-based text viewing require a separate change. Image previews are static, downsampled and fit-to-panel. SVG, PDF and arbitrary binary preview are not added.

## Verification

- Core: WorkspaceFilePreviewTests (3 tests): text and images over 2 MiB, legacy payloads, unsupported binary, directories, traversal, symlink escape.
- ClientNative: WorkspaceSourceFileTests (10 tests): large text, decoded/corrupt images, loading completion, navigation during load, endpoint origin, caching, refresh, failure.
- Native window: WorkspaceSourceFileRenderingTests (2 tests), enabled with SLOPPY_RUN_INTERACTIVE_UI_TESTS=1. A valid JPEG plus trailing bytes exceeding 3 MiB exercises loading, preview and reload; native transcript link/line scrolling also passes.
- Screenshots of the actual production view in an isolated native test window: .sloppy/verification/file-preview/file-loading.png and file-jpeg-preview.png. These do not prove deployment to a running Core. The text about size in the image is fixture artwork, not a UI error.
- Builds passed: swift build --product sloppy; ClientNative swift build --product SloppyClient; XcodeBuildMCP macos build for SloppyClient-macOS.
- Existing native transcript test emits AttributeGraph cycle diagnostics despite passing assertions. Dependency/concurrency build warnings remain outside this fix.
