# Validation rules

Run the smallest meaningful check first, then the matching profile. Use production paths
and deterministic fixtures. Swift tests use `import Testing`, `@Test`, `#expect`; Node and
Python tooling use their existing suite conventions. A source-text assertion does not
substitute for material runtime behavior.

`.agents/validation.json` selects profiles. The runner prints compact status lines and a
report path, keeping detailed output in ignored `.artifacts/contribution/`. Read the failed
log before changing code. Do not weaken profiles, omit tests or broaden exclusions to get green.

See [commands](workflow.md) for setup and TDD. Missing tools and unavailable platforms are
`blocked`; explicit irrelevant checks are `not_applicable`. `deferred` exists only for
publication and still requires mapped CI results. Partial CI-lane evidence cannot close tasks.

Initial style checks are content/diff checks, Ruff and a narrow SwiftLint configuration.
Dashboard has no ESLint configuration; typecheck is analysis, not an ESLint result.
Bandit covers Python tooling, Swift compiler diagnostics/SwiftLint cover Swift, and `tsc`
covers Dashboard types. These do not establish universal security or dynamic coverage.

Root/shared Swift changes select release builds of both executables and the root suite;
shared protocol/plugin/control changes also select client checks. Dashboard selects its
existing Node tests, typecheck and Vite build. Authored docs select VitePress. Files under
`.agents/knowledge/` do not trigger product builds merely because they describe the product.

Supply real reviewed runtime/platform/dependency argv recipes where required. Empty or
fully skipped tests, timeouts and changed logs invalidate evidence. A fresh passing report
binds the final source/index/new-file snapshot and current required inventory. Individual successful
built-in checks may be reused when their dependency sources, execution contract, relevant tools,
selected environment and original log hashes match. A plan edit does not invalidate native tests.
Manifests, resources (including ignored source resources), dependencies and tooling do. Unknown
recipes rerun conservatively. Failed or blocked checks and partial/quick profiles are not reused.
Native reuse explicitly includes resolved checkout/artifact trees in the command's Swift scratch
directory. Apple-client checks with external dependency selection and external scratch roots rerun.

Hook installation preserves previous hooks and rejects conflicts before changing any hook.
Pre-commit rejects partial staging/unstaged tracked changes; pre-push requires a clean outgoing
commit. Neither command resets, stashes or cleans the contributor's files.

Tool freshness includes installed TypeScript/Vite/VitePress compiler files and npm install metadata.
Node-backed checks are deliberately not reused, because their ignored transitive dependency
graph can change independently of tracked source. Initialized submodule worktrees are recursively
fingerprinted, including dirty contents. Git commands disable optional filesystem-monitor caching
per invocation and terminate their process tree on timeout; contributor Git configuration is untouched.
