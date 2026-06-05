# Planner and Executor Model Routing PRD

## 1. Executive Summary

- **Problem Statement**: Agents currently have one primary native model, so expensive reasoning and hands-on execution use the same model even when the operator wants a stronger planner and a cheaper executor.
- **Proposed Solution**: Add per-agent Planner Model and Executor Model settings. Native agent runs always plan first with the planner model, then execute with the executor model; when no planner is configured, planner falls back to executor.
- **Success Criteria**:
  - Existing agents without `plannerModel` continue to run without manual migration.
  - Operators can configure executor and planner models from the agent Models settings.
  - Saved configs round-trip `plannerModel` through API, disk, and Dashboard.
  - Runtime metadata distinguishes planner and executor model IDs.
  - Invalid planner model IDs are rejected using the same model validation policy as executor IDs.

## 2. User Experience & Functionality

- **User Personas**:
  - Operator configuring a coding agent for cost and quality balance.
  - Developer debugging why a native agent chose a specific model.
  - Power user running multiple agents with different planning/execution budgets.

- **User Stories**:
  - As an operator, I want to choose an Executor Model so routine tool and code work can run on a cheaper model.
  - As an operator, I want to choose a Planner Model so every native run starts with a stronger reasoning model.
  - As an operator, I want old agents to keep working so migration does not break existing workspaces.
  - As a developer, I want planner/executor choices visible in config and logs so model routing is debuggable.

- **Acceptance Criteria**:
  - The agent Models section labels the existing default model picker as `Executor Model`.
  - The agent Models section adds a `Planner Model` picker using the same available model catalog.
  - Empty Planner Model is valid and means `plannerModel = executorModel` at runtime.
  - Native runtime still requires a non-empty executor model.
  - ACP runtime does not require native model settings.
  - `GET /v1/agents/{agentId}/config` includes `plannerModel`.
  - `PUT /v1/agents/{agentId}/config` accepts `plannerModel`.

- **Non-Goals**:
  - No global automatic model quality ranking in MVP.
  - No hidden dependency on Settings > Model routing aliases for planner/executor selection.
  - No tool access for the planner in MVP.
  - No multi-agent planner hierarchy in MVP.

## 3. AI System Requirements

- **Tool Requirements**:
  - Planner step: no tools; produces a concise execution plan.
  - Executor step: keeps existing tool access, approval policy, and loop guards.
  - Dashboard uses existing provider model catalog and searchable model picker behavior.

- **Evaluation Strategy**:
  - Unit tests verify `plannerModel` persistence, API coding, and fallback.
  - Runtime tests verify selected planner/executor IDs are computed deterministically.
  - Manual eval: one agent with `plannerModel != executorModel` should show planner/executor metadata and complete a simple tool-capable task.

## 4. Technical Specifications

- **Architecture Overview**:
  - `selectedModel` remains the stored executor model for backward compatibility.
  - `plannerModel` is added as an optional field to agent config API and disk config.
  - Runtime computes `executorModel = perTurnOverride || selectedModel`.
  - Runtime computes `effectivePlannerModel = plannerModel || executorModel`.
  - Planner output is injected as structured context before executor execution.

- **Integration Points**:
  - `Sources/Protocols/APIModels.swift`: add `plannerModel` to `AgentConfigDetail` and `AgentConfigUpdateRequest`.
  - `Sources/sloppy/Agent/AgentCatalogFileStore.swift`: read/write/canonicalize `plannerModel`.
  - `Sources/sloppy/CoreService+Agents.swift`: widen available model validation for `plannerModel`.
  - `Sources/sloppy/Agent/AgentSessionOrchestrator.swift`: compute planner/executor model IDs for native runs.
  - `Dashboard/src/features/agents/components/AgentConfigTab.tsx`: show Executor Model and Planner Model pickers.
  - `Dashboard/src/features/agents/AgentsView.tsx`: no routing policy should live here; it continues to host the agent config tab.

- **Security & Privacy**:
  - Model IDs are configuration metadata, not secrets.
  - Planner receives the user request and session context but no tool credentials.
  - Executor remains subject to existing tool approval, filesystem, and command policies.

## 5. Risks & Roadmap

- **Phased Rollout**:
  - MVP: persist planner model, expose UI, compute planner/executor model IDs with fallback.
  - v1.1: add planner step to native execution and stream metadata for plan/executor phases.
  - v2.0: add eval-backed routing policies, cost/latency summaries, and optional per-mode routing.

- **Technical Risks**:
  - Adding a planner step to every native run can increase latency and cost.
  - If planner output is too verbose, executor context budget can shrink.
  - Existing clients may ignore `plannerModel`; API must remain backward-compatible.
  - Runtime must avoid planner tool access to keep the role split clear.
