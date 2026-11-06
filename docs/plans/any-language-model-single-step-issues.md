# AnyLanguageModel single-step follow-ups

Independent review is deferred by the user's instruction on 2026-11-06.

- The legacy `respond` / `streamResponse` provider orchestration is preserved rather
  than rewritten around the new declaration-only API. Its generation options and
  automatic tool behavior remain a separate compatibility surface. A future migration
  needs its own compatibility scope; the native Sloppy step path now shares the library
  transport and codecs.
- The SDK/library boundary uses Codable conversion for request, response and JSON
  values. This preserves existing SDK persistence/wire contracts without introducing a
  library dependency on Sloppy. Measure allocation cost before replacing this with
  explicit field conversion.
- Live provider accounts and Apple-platform integration are not established by local
  Linux fixture tests. No live-backend or macOS result is claimed.
- The existing `GenerableMacroTests.swift` cannot compile under the local Swift 6.2.4
  Linux toolchain: `@Generable` expands a multiline description into an unterminated
  string literal. It is unrelated to the moved HTTP implementation. The isolated
  compatibility harness excludes that single file; it does not change its source or
  the library's production manifest. A complete library test-suite result is therefore
  still blocked by this macro issue.
- Eleven existing library Ollama integration tests require an actual server at
  `localhost:11434`, unavailable in this environment. They fail with connection refused
  in the broad run and are explicitly skipped in the subsequent offline run. Native
  Ollama single-step fixture contracts still run, including streaming, tool calls,
  thinking, usage and cancellation.
- Root SwiftPM resolution warns about duplicate package identities for EventSource
  (local and remote) and swift-syntax (apple and swiftlang URLs). These pre-existing
  dependency chains may become errors in a future SwiftPM version.
- The first parallel Core Claude Code run hit `NSPOSIXErrorDomain` code 26 (`Text
  file busy`) while launching freshly written CLI fixture executables. A serial rerun
  of the identical compiled suite passed (15 executed, one installed-CLI test skipped).
  The fixture launch race remains a follow-up; no retry was added to production code.

## Local evidence

- Before extraction: all 28 single-request provider contract tests passed.
- The credential-refresh regression has retained runner Red/Green logs: a 401 retry
  previously sent `Bearer old-key`; after the fix it sends `Bearer new-key` once.
- Final offline Swift run: 368 tests selected in 42 suites, 296 executed successfully
  and 72 skipped by their existing availability/key conditions. The 11 server-dependent
  Ollama tests are additionally excluded with `--skip OllamaLanguageModelTests`.
  New library tests exercise both old session APIs over a configured HTTP fixture.
- Documentation build passed; the contribution runner's quick Code content check passed.
- The actual root package compiled and linked `sloppy`; its Claude Code provider suite
  passed on serial rerun, including the public SDK Anthropic codec compatibility adapter
  and signed tool-history replay. This is a debug build, not a release/CI parity claim.
- Linux harness sources are copied byte-for-byte from the workspace. The harness only
  adds the owning library/usage test targets and excludes the macro test described above;
  it does not alter the production package manifest or production Swift source.
