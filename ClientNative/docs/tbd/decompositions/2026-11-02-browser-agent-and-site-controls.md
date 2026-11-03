# Browser agent and site controls — decomposition map

- Created: 2026-11-02.
- Reference: owner request in this chat: agent tab management/grouping, interaction cursor with agent portrait, browser todos/notes, HTTP consent, camera/location/microphone permissions, site data controls, full reload, Handoff status.
- Trunk/current branch: `main`. Existing dirty changes belong to other work and must be preserved.
- Delivery: local implementation and validation; commits, publication, installation and deployment are separate outcomes.
- Budgets: added + removed reviewable lines, target ≤600, cap 1000 per slice; docs/generated/vendor files excluded.
- Approval: full map and recommended strategy approved by the owner on 2026-11-02.
- Platforms: macOS, iPhone and iPad for browser capabilities; Command-Shift-R is a macOS shortcut. Keep the existing visionOS manual-browser path compatible; do not advertise unsupported automation there.

## Verified starting point

- `BrowserWorkspaceState` already persists tabs and groups and owns `BrowserOrganizerStore` with local notes/tasks.
- `WorkspaceBrowserSession` binds a conversation to one retained page; `BrowserAgentChatState.synchronizeBrowser` retargets that page when the selected tab changes.
- Existing commands include open/navigate/read/click/type/scroll/screenshot/evaluate. `close` currently navigates to `about:blank`; it does not close a Browse tab.
- `WorkspaceBrowserCommand.Input` has no structured workspace/group/note/task command payloads. Core and client need additive, compatible protocol changes.
- `WorkspaceBrowserToolRuntime` implements navigation and UI delegates. The inspected browser sources have no app-owned HTTP consent or camera/microphone/location permission policy, and no full-reload action. Existing OS/WebKit permission behavior must be verified, not assumed to be absent.
- `BrowserConnectionSecurityButton` currently presents connection/certificate information on macOS, a suitable entry point for site controls.
- `BrowserHandoffModifier` is attached in `RootShellView`, advertises selected Browse HTTP(S) pages, and accepts continuation into Sloppy. `BrowserContinuityTests` covers eligibility, sanitized URLs and invalid input. Current documentation explicitly leaves real transfer between signed devices as manual acceptance.

## Capability inventory

- List, create, select and close actual Browse tabs by stable IDs without confusing page and tab identity.
- Let the model propose semantic groups from bounded tab context and apply explicit group commands; no keyword-based classification in application code.
- Let the agent create browser notes and todos using the existing local organizer and return stable IDs.
- Display an agent cursor with restrained glow and the active agent's existing portrait during actual page interactions.
- Require consent before HTTP navigation, including HTTPS-to-HTTP redirects and agent-driven navigation; remember and revoke site decisions.
- Request and persist per-site camera, microphone and location decisions while respecting OS permissions and requesting-frame origin.
- Expose per-site decisions and explicit cache/cookie/site-storage deletion in browser UI.
- Clear browser caches and reload the active page using Command-Shift-R, while preserving cookies and stored logins.
- Confirm Handoff status and perform real device acceptance when compatible signed devices are available.

## Slices

| # | Slice | Purpose | Strategy | Budget | Depends on | Status |
|---|-------|---------|----------|--------|------------|--------|
| 1 | Agent controls Browse tabs | Add end-to-end list/create/select/close commands targeting actual workspace tabs. | Additive, capability-negotiated commands; existing page commands remain compatible. | 800 | — | in-review |
| 2 | Agent groups tabs semantically | Expose title/URL context and explicit create/rename/move group operations to the model. | Reuse existing persisted groups; complete new command family. | 500 | 1 | in-review |
| 3 | Agent creates browser notes and todos | Save agent-created entries in the same organizer used by the browser UI. | Additive commands with validated structured payloads and visible results. | 550 | 1 | in-review |
| 4 | Visible agent interaction cursor | Show the cursor, click feedback and current agent portrait at actual interaction targets. | Self-contained presentation driven by typed runtime actions. | 550 | — | in-review |
| 5 | Remember HTTP consent | Ask before HTTP navigation and allow users to revoke saved site decisions. | Complete navigation policy, prompt and persistent decision controls together. | 600 | — | in-review |
| 6 | Camera and microphone site permissions | Add origin-bound ask/allow/block decisions and permission controls. | Self-contained public WebKit/OS integration, shared site-controls UI. | 600 | 5 | in-review |
| 7 | Location site permissions | Request and revoke location access through supported platform mechanisms. | Self-contained public platform integration, with capability limits verified first. | 550 | 5 | in-review |
| 8 | Clear a site's browser data | Let users remove the selected site's caches, cookies and website storage. | Explicit, bounded user action in the site-controls UI. | 500 | 5 | in-review |
| 9 | Full reload shortcut | Clear browser cache data, then reload the active page with Command-Shift-R. | Complete native command with explicit cache-only semantics. | 350 | — | in-review |

Slice 1 exceeds the 600-line target because protocol negotiation, Core tool routing, client workspace execution and cross-version tests must form one usable tab-control feature. Cap it at 1000; split again before coding if discovery exceeds that estimate. The Core repository is outside this chat's writable root: request the required execution escalation when concrete edits there are ready.

## Slice details and acceptance

### 1 — Agent controls Browse tabs

- In scope: stable workspace/tab identifiers, capability advertisement, bounded tab list, create/select/close, selected-tab fallback, binding cleanup after close, unchanged retained pages across selection. Check session ownership and reject stale IDs.
- Out of scope: grouping and organizer operations; automatically closing unrelated Work tabs.
- Ships safely because: old clients retain their existing page-command semantics; unsupported workspace capabilities return a clear error. New workspace commands are exposed only when the bound client supports them.
- Verify: protocol compatibility, two tabs with different form values, closing active/background/last tab, switching tabs during a pending command, Core/client routing and release builds.
- Cleanup owed: none.

### 2 — Agent groups tabs semantically

- In scope: existing group persistence, explicit group names and member tab IDs, bounded title/URL context, semantic planning by the model.
- Out of scope: localized word lists or hard-coded title/URL categories; inventing a second grouping store.
- Ships safely because: existing tab/group UI remains the authority and each tool result reports actual saved membership.
- Verify: group creation/movement/rename, missing IDs, restart persistence, no loss of page/form state.
- Cleanup owed: none.

### 3 — Agent creates browser notes and todos

- In scope: validated title/body or details, optional source page, supported due date/priority, return entry IDs; reuse organizer save paths and existing browser UI.
- Out of scope: project-task creation, notifications, cloud sync, unsolicited deletion/editing of existing entries.
- Ships safely because: additive create actions save through the existing device-local organizer and report the persisted result. Command delivery retains the current no-automatic-replay rule.
- Verify: agent-created entries visible in Notes/Tasks, persisted after recreation, malformed input rejected, source association maintained.
- Cleanup owed: none.

### 4 — Visible agent interaction cursor

- In scope: actual runtime click/type/scroll targets, native presentation above WebKit, restrained glow, current agent portrait beside the cursor, click feedback, page-relative coordinate conversion, Reduce Motion and input pass-through.
- Out of scope: fictitious cursor motion for arbitrary JavaScript execution, generating new agent artwork, taking control of the user's system pointer.
- Ships safely because: visual state follows typed actions and clears on cancellation/navigation/tab close; it never captures user input or becomes page content.
- Verify: interaction in a scrolled page and split view, correct agent portrait, hidden/offscreen targets, cancellation, accessibility settings; visually inspect macOS and mobile.
- Cleanup owed: none.

### 5 — Remember HTTP consent

- In scope: app-owned prompt before top-level HTTP loads, including restored tabs, links, redirects, agent navigation and new-window destinations; allow once, always allow this site, cancel; persisted decisions and reset controls. Explicit HTTP loopback follows the same consent model.
- Out of scope: weakening TLS certificate validation or silently retrying failed HTTPS as HTTP; wholesale mixed-content policy replacement.
- Ships safely because: HTTPS retains its current behavior and HTTP resumes only following the user's applicable decision. Prompt cancellation/tab closure resolves pending navigation cleanly.
- Verify: no HTTP fixture request before consent, one-time versus remembered approval, redirect interception, navigation cancellation, restart and reset behavior. Update existing HTTP fixtures to make policy choices explicit.
- Cleanup owed: none.

### 6 — Camera and microphone site permissions

- In scope: public WebKit permission hooks, separate camera/microphone ask/allow/block choices, requesting origin and frame checks, OS permission denial, reset controls, required usage descriptions/signing entitlements for applicable targets.
- Out of scope: treating model/tool approval as site permission, bypassing system permission, inferring approval from URL/title text.
- Ships safely because: requests go through origin-bound policy and OS authorization; missing or unavailable access never appears as granted.
- Verify: individual and combined media requests, persistent choices, cross-origin frame requests, system denial, revocation/re-request; runtime checks on signed builds where OS authorization requires them.
- Cleanup owed: none.

### 7 — Location site permissions

- In scope: investigate supported public WebKit/native location permission paths on each target first, then integrate ask/allow/block and revocation where supported. Keep requesting origin and OS authorization explicit.
- Out of scope: private selectors, fabricated browser permission APIs, silently replacing website geolocation with an imprecise coordinate source.
- Ships safely because: unsupported platform behavior is reported honestly; location remains unavailable without the required user and system decisions.
- Verify: real page location request, OS denied/unavailable, remembered decision and reset, navigation during request, origin isolation. Record any platform limitation as unfinished acceptance rather than claiming parity.
- Cleanup owed: none.

### 8 — Clear a site's browser data

- In scope: clear data for the selected site through public website-data APIs; separate cache-only and cookies/site-storage actions; explain that removing cookies signs the user out; identify affected data scope accurately. Add mobile access to site controls.
- Out of scope: silently erasing unrelated sites, browsing history, notes, tasks or tab groups.
- Ships safely because: deletion is an explicit user action with visible scope and success/failure, using shared browser data-store behavior.
- Verify: two independent fixture sites, cache/cookie/storage removal on the selected site, preservation of the other site and local organizer, refreshed loaded-page state.
- Cleanup owed: none.

### 9 — Full reload shortcut

- In scope: Command-Shift-R plus a discoverable Reload Without Cache menu command; clear supported cache types from the shared browser profile and wait for completion before reloading the active page. Cache scope includes other tabs sharing that profile.
- Out of scope: deleting cookies, local storage, sign-in state, history, notes/tasks or saved permissions; claiming cache bypass clears service-worker registrations.
- Ships safely because: the action is user-invoked, normal Command-R remains independent, cache cleanup failure is visible.
- Verify: changed cached fixture resource is fetched again, shortcut reaches the active browser, cookies and local storage survive, no action on an absent page, pending operation/cancellation behavior.
- Cleanup owed: none.

## Handoff acceptance (existing implementation, no new feature slice)

On compatible signed Mac and iPhone/iPad apps, confirm continuation in both directions, including app cold launch and no Core connection. Verify title, query and fragment, stripping URL credentials, and no advertisement for blank/failed pages or Work. This manual acceptance is still outstanding; existing source/tests are not proof of physical transfer. HTTP continuations must obey slice 5 consent.

## Strategy alternatives for approval

- Recommended: complete independent increments above, reusing existing state owners; additive capabilities negotiated at the client/Core boundary. No temporary toggle or replacement browser implementation, no cleanup debt.
- Alternative: gate all new agent workspace command dispatch at `WorkspaceBrowserSession.execute` and new browser UI entry points behind one temporary browser-capabilities flag. Existing page navigation would still need the complete HTTP policy. This delays usable features, introduces additional gate points, and requires an explicit flag-removal slice before adopting that option.

## Validation and delivery

- Smallest affected Swift Testing suites first; real WebKit fixtures for navigation, permissions and data lifetime where feasible. Visual inspection for prompts, site controls and cursor.
- Client macOS Release and iOS Simulator builds; affected Core protocol/tool/bridge tests and `sloppy`/`SloppyNode` Release builds for slices changing Core. Run the required full suites after focused checks; record existing failures separately from new regressions.
- Initial map creation was discovery-only; implementation and verification evidence are recorded below.

## Decision log

- 2026-11-02: Inspected existing tab/workspace binding, organizer, runtime, Handoff implementation, continuity tests, project configuration and browser docs. Reuse current groups/notes/tasks and add agent-facing operations instead of duplicate stores. Treat Handoff as existing implementation with outstanding real-device acceptance.
- 2026-11-02: Proposed cache semantics: full reload clears caches across the shared profile but preserves cookies/storage; per-site data deletion is separate. Awaiting approval of the full decomposition and recommended integration strategy.

- 2026-11-02: Slice 1 implemented locally (~230 reviewable lines relative to the pre-task dirty baseline), client state test passed, Core bridge 9/9 and interactive browser/chat 6/6 passed. No PR, commit or deployment. Continuing the approved local sequence.

- 2026-11-02: Slice 2 implemented locally (~130 reviewable lines); two workspace/group tests pass, including atomic rejection of stale tab members and persistence. Core compilation is rechecked with the following organizer increment.

- 2026-11-02: Slice 3 implemented locally (~170 reviewable lines); workspace/organizer tests 3/3 passed with structured validation, source credential sanitization and persistent entries.

- 2026-11-02: Slice 4 implemented locally (~190 reviewable lines); five cursor/workspace tests passed. Native overlay render inspected; cursor/portrait are visible and pass mouse events through.

- 2026-11-02: Slices 1–3 Core catalog/bridge verification now passes 30/30 after fixing array schema. Slice 5 HTTP policy tests pass 4/4; a real server redirect is blocked before the target receives traffic, cancellation cannot resume navigation. Existing HTTP fixtures now inject explicit consent into isolated stores.

- 2026-11-02: Slice 6 implemented locally (~210 reviewable lines plus generated project); 19 tests in six permission/runtime/session/workspace suites pass. System camera/microphone decisions are injected in tests; no physical recording or real OS grant was requested.

- 2026-11-02: Slice 7 public callback implemented and compiled using its documented ObjC selector, with OS protocol capability detection. Eight permission/workspace tests pass. Installed SDK lacks the callback; on such systems location remains system-managed and custom controls are disabled. Real geolocation permission acceptance remains outstanding on a supporting OS.

- 2026-11-02: Slice 8 implemented locally (~180 reviewable lines); 7/7 data/permission tests passed, including deletion of one real WebKit origin while another retains cookies and localStorage. WebKit record scope is shown before deletion.

- 2026-11-02: Slice 9 implemented locally (~100 reviewable lines). Nine reload/data/permission tests pass: shared cache removal clears real Fetch Cache, refetches the page, and preserves cookies and localStorage. All slices are local review candidates, with final broad/platform validation in progress; slice 7 has the OS capability limitation above.
