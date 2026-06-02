# PRD: Project Memory for Agents

Status: Internal as-is specification for maintainers and coding agents  
Date: 2026-06-02  
Audience: Sloppy engineers and repository-aware agents  
Public docs: Excluded from VitePress via `srcExclude`

## 1. Executive Summary

- **Problem Statement**: Sloppy agents need durable project context across sessions, but engineers need a precise contract for how that context is loaded, written, scoped, and evaluated. Without a shared specification, project memory can drift into duplicated facts, stale bootstrap content, or unsafe persistence of transient/sensitive data.
- **Proposed Solution**: Treat current project memory as a two-layer system: workspace-private markdown at `~/.sloppy/projects/<projectId>/.meta/MEMORY.md` for compact project-wide notes, plus project-scoped semantic/procedural memory entries saved through `memory.save` and queried through project memory APIs.
- **Success Criteria**:
  - Agent sessions with a valid `projectID` and stored `repoPath` include `[.meta/MEMORY.md]` in bootstrap when the workspace-private memory file exists.
  - `project.meta_memory_set` writes only to the Sloppy workspace project directory, never to the source repository, and rejects content over 3000 characters.
  - Memory checkpoints save project-scoped facts only after `memory.search` in the intended scope and only when confidence is `>= 0.8`.
  - Duplicate project memory entries created by repeated checkpoints stay below 5% in regression evals.
  - Golden memory evals show `>= 90%` correct use of relevant project memory when task answers depend on it, with zero cross-project contamination.

## 2. User Experience & Functionality

- **User Personas**:
  - Core engineer: maintains project context loading, bootstrap rendering, storage paths, and API behavior.
  - Runtime/AI engineer: measures whether memory improves model context without adding noise or unsafe persistence.
  - Agent/tooling engineer: updates project tools, checkpoint prompts, or task lifecycle hooks while preserving memory boundaries.
  - Repository-aware coding agent: reads this document before changing project memory code.

- **User Stories**:
  - As a core engineer, I want project memory loaded into agent bootstrap so that project conventions and durable decisions are available before tool use.
  - As an agent, I want to save durable project facts with explicit project scope so that future sessions can retrieve relevant context.
  - As a runtime engineer, I want memory checkpoints constrained by tools, scope, and confidence so that transient or sensitive content is not persisted.
  - As an evaluator, I want reproducible memory quality tests so that prompt/runtime/model changes do not silently degrade context quality.
  - As a maintainer, I want markdown project memory kept outside the source repository so that private workspace notes do not become repo artifacts.

- **Acceptance Criteria**:
  - `ProjectContextLoader` loads repository docs (`AGENTS.md`, `CLAUDE.md`, `SLOPPY.md`), workspace-private `.meta/MEMORY.md`, and `.skills/**/SKILL.md` within configured character limits.
  - `projectBootstrapMarkdownForAgentSession(projectID:)` renders `.meta/MEMORY.md` as `[.meta/MEMORY.md]` when present.
  - `refreshProjectContext(projectID:)` applies the same rendered bootstrap to linked project channels and reports `.meta/MEMORY.md` in `loadedDocPaths`.
  - `project.meta_memory_set` validates project existence, creates `projects/<projectId>/.meta/`, writes `MEMORY.md`, and returns `path` plus `chars`.
  - Memory checkpoint instructions allow only `visor.status`, `memory.search`, `memory.save`, `agent.documents.set_user_markdown`, `agent.documents.set_memory_markdown`, and `project.meta_memory_set`.
  - Project-scoped memory entries are returned by `/v1/projects/:projectId/memories` and `/v1/projects/:projectId/memories/graph`.
  - Updating a project task to `needs_review` requests a project memory checkpoint for the current agent/session/project/task.

- **Non-Goals**:
  - Do not add a new project memory UI in this scope.
  - Do not change embedding, ranking, or graph relation algorithms in this scope.
  - Do not share project memory across projects unless a future scoped-sharing design is accepted.
  - Do not write project `.meta/MEMORY.md` into the source repository.
  - Do not persist secrets, credentials, tokens, private URLs, low-confidence guesses, runtime bulletins, or one-off task status as project memory.

## 3. AI System Requirements

- **Tool Requirements**:
  - `project.meta_memory_set` writes the full workspace-private `.meta/MEMORY.md` body for a specified project.
  - `memory.search` must be called before checkpoint writes to detect existing facts and avoid duplicates.
  - `memory.save` stores durable project facts with `scope_type: project`, `scope_id: <projectId>`, `source_type: memory_checkpoint`, `source_id: <sessionId>`, and metadata containing `agentId`, `sessionId`, and checkpoint reason.
  - `project.task_update` triggers `requestProjectMemoryCheckpoint` when status moves to `needs_review`.
  - Agent session bootstrap must include project context before the model begins task work.

- **Evaluation Strategy**:
  - Bootstrap inclusion eval: create a project with repo docs and workspace-private `.meta/MEMORY.md`; assert bootstrap includes `[.meta/MEMORY.md]` and expected content.
  - Scope isolation eval: create two projects with conflicting memory facts; assert project A prompts do not use project B facts.
  - Deduplication eval: run checkpoint twice over the same transcript; assert no second semantically duplicate project memory entry is written.
  - Safety eval: include secrets, tokens, credentials, and private URLs in checkpoint transcript; assert zero `memory.save` and zero `.meta/MEMORY.md` writes for those values.
  - Relevance eval: benchmark task prompts requiring project conventions/decisions; target `>= 90%` answers citing or applying the correct memory.
  - Staleness/conflict eval: introduce conflicting old/new project facts; assert checkpoint avoids writing unless transcript clearly resolves the conflict.

## 4. Technical Specifications

- **Architecture Overview**:
  - `ProjectContextLoader` reads project bootstrap sources from the repository root and accepts an optional workspace-private project memory URL.
  - `CoreService.projectMetaMemoryFileURL(projectID:)` resolves markdown memory to `workspaceRoot/projects/<projectId>/.meta/MEMORY.md`.
  - `CoreService.projectBootstrapMarkdownForAgentSession(projectID:)` renders loaded project context for agent sessions without writing to channels.
  - `CoreService.refreshProjectContext(projectID:)` renders the same project context and applies it to linked runtime channels.
  - `ProjectMetaMemoryTool` is the only agent-visible project tool that writes `.meta/MEMORY.md`.
  - Memory checkpoint runs a shadow session with a strict tool allowlist and persists only high-confidence durable facts.
  - Project memory APIs filter `MemoryEntry` records that belong to the requested project scope and return list/graph views.

- **Integration Points**:
  - Loader: `Sources/sloppy/Projects/ProjectContextLoader.swift`
  - Bootstrap rendering and project memory paths: `Sources/sloppy/CoreService+Projects.swift`
  - Markdown write tool: `Sources/sloppy/Tools/AgentTools/Project/ProjectMetaMemoryTool.swift`
  - Checkpoint bootstrap and action recording: `Sources/sloppy/CoreService+MemoryCheckpoint.swift`
  - Project memory list/graph APIs: `Sources/sloppy/CoreService+Agents.swift` and `Sources/sloppy/Gateway/Routers/ProjectsAPIRouter.swift`
  - Task checkpoint trigger: `Sources/sloppy/Tools/AgentTools/Project/ProjectTaskUpdateTool.swift`
  - Regression coverage: `Tests/sloppyTests/ProjectMemoryPathTests.swift`

- **Security & Privacy**:
  - `.meta/MEMORY.md` is workspace-private and must remain outside the source repository.
  - Project IDs must be normalized and project existence checked before writing project markdown memory.
  - `AgentMarkdownLimits.projectMetaMemoryMarkdownMaxCharacters` caps `.meta/MEMORY.md` at 3000 characters.
  - Checkpoints must not persist secrets, credentials, tokens, private URLs, transient runtime bulletins, low-confidence guesses, or duplicate facts.
  - Project memory entries must carry explicit scope/source metadata so API filters and future audit flows can distinguish project memory from agent-global memory.

## 5. Risks & Roadmap

- **Phased Rollout**:
  - MVP/as-is hardening: preserve current two-layer memory model, bootstrap injection, checkpoint allowlist, project memory APIs, and existing tests.
  - v1.1: add golden eval fixtures for relevance, deduplication, safety, cross-project isolation, and conflict handling.
  - v1.2: expose memory quality metrics to maintainers: duplicate rate, stale/conflict rate, safety rejection count, and relevance pass rate.
  - v2.0: design richer memory freshness/conflict resolution without expanding prompt-only heuristics or weakening explicit project scope.

- **Technical Risks**:
  - Context bloat can crowd task-specific information when repo docs, skills, and project memory are all loaded.
  - Markdown memory can become stale or contradict structured project-scoped memory entries.
  - Repeated checkpoints can create semantically duplicate memory without strong search/eval coverage.
  - Project scope bugs can leak memory across projects.
  - Overly conservative checkpoint rules can skip useful durable decisions.
  - Expanding checkpoint tools can accidentally permit writes or reads outside the intended memory boundary.
