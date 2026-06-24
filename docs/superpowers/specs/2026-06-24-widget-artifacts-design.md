# Widget Artifacts Design

Date: 2026-06-24

## Goal

Sloppy should let users ask an agent to create a bounded start-page widget, store the result as an artifact, browse artifacts from Dashboard and the SloppySafari sidebar, and place created widgets on the SloppySafari start page grid alongside website shortcuts.

## User Experience

On the SloppySafari start page, Customize gains a Widgets area below the existing start page and shortcut controls. The primary action is `Describe your widget`. It opens a text field where the user describes the desired widget and chooses a fixed widget size. After submission, Sloppy creates an agent-backed widget artifact. When generation completes, the widget appears in Customize and can be added to the start page grid.

The start page grid contains two item kinds:

- `shortcut`: title, URL, favicon URL.
- `widget`: artifact id, title, fixed size.

The SloppySafari sidebar gains an `Artifacts` item. Selecting it shows an inline artifact list, similar to Sessions, with widget previews or compact artifact metadata. Dashboard also gains a top-level `Artifacts` tab with a gallery/list view for all artifacts.

## Widget Contract

Widget artifacts are stored under:

```text
.sloppy/artifacts/widgets/<artifact-id>/
```

Each widget artifact contains:

```text
manifest.json
index.html
assets/...
```

`manifest.json` includes:

- `id`
- `title`
- `kind: "widget"`
- `createdAt`
- `size`
- `entry: "index.html"`
- optional `description`

Supported sizes are intentionally limited:

- `small`: 160 x 120
- `medium`: 320 x 180
- `large`: 320 x 320

The generation prompt given to the agent must include this contract and the selected size. Generated UI must fit inside the selected dimensions without resizing the host layout.

## Rendering And Safety

Dashboard and SloppySafari render widget artifacts through sandboxed iframes. The host owns the size, border, grid placement, loading state, and error state. The widget owns only its internal visual content.

Initial implementation renders self-contained widgets. Network access, host API access, and privileged browser actions are out of scope for this version. That keeps generated code useful for clocks, notes, static dashboards, counters, visualizations, and generated mini-tools without letting artifact code control the extension or Dashboard shell.

## Core API

Existing `/v1/artifacts/:artifactId/content` remains supported. Core adds artifact metadata and listing endpoints:

- `GET /v1/artifacts`
- `GET /v1/artifacts/:artifactId`
- `GET /v1/artifacts/:artifactId/content`
- `GET /v1/artifacts/:artifactId/widget`
- `POST /v1/artifacts/widgets/generate`

`GET /v1/artifacts` returns records suitable for both Dashboard and SloppySafari:

- `id`
- `title`
- `kind`
- `mediaType`
- `createdAt`
- `previewText`
- `widget` metadata when applicable

`POST /v1/artifacts/widgets/generate` accepts a user prompt and widget size. It creates or delegates to an agent session, instructs the agent to create a widget artifact using the contract, stores it under `.sloppy/artifacts/widgets/<artifact-id>/`, persists metadata, and returns the artifact record or a generation job/session reference when generation is asynchronous.

## Persistence

Core extends persisted artifacts from id/content-only storage to metadata-aware records. SQLite and the in-memory fallback store enough metadata to list artifacts without loading each content payload.

Widget bundle files live on disk under `.sloppy/artifacts/widgets`. The database stores metadata and the bundle path. The existing runtime artifact content lookup can still hydrate legacy artifacts.

## Dashboard

Dashboard adds `artifacts` as a top-level route and sidebar item. The first version provides:

- grouped artifact gallery/list
- type filter with at least `All` and `Widgets`
- widget preview cards using the same fixed-size iframe renderer
- empty, loading, and error states

The view uses `Dashboard/src/shared/api/coreApi.ts` for artifact APIs.

## SloppySafari

The extension adds:

- sidebar `Artifacts` item
- message handlers in `panel.js` for listing artifacts and requesting widget content/preview URLs from Core
- Customize widget generator section
- start page grid rendering for shortcuts and widget cards
- settings persistence for selected grid items

The extension keeps the existing new-tab behavior and chat transition behavior. Widgets do not replace the chat composer; they render below it in the start page grid.

## Error Handling

If Core is unavailable, SloppySafari shows the existing connection-style error in the Artifacts list and disables widget generation. If a widget bundle is missing or invalid, hosts show a fixed-size broken-widget card with the artifact title and a concise error. Invalid widget sizes are rejected by Core and ignored by clients.

## Tests And Verification

Core tests cover artifact metadata persistence, list endpoint responses, widget generation request validation, and legacy content lookup compatibility.

Dashboard verification covers route parsing, sidebar registration, API client behavior, and build/typecheck.

SloppySafari tests cover sidebar Artifacts rendering, Customize widget controls, start grid mixed shortcut/widget rendering, and fixed-size widget frame markup.

Relevant commands:

```text
swift test --filter Artifact
cd Dashboard && npm run typecheck && npm run build
cd Apps/SloppySafari/Extension && npm test
```

## Out Of Scope

- live widget data connectors
- arbitrary host API access from widgets
- shared/public artifact permissions beyond local listing labels
- drag-and-drop grid layout editor beyond selecting widgets for the grid
