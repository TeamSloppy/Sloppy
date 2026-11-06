# Unified native agent loop ownership

Date: 2026-11-04. Status: accepted; implementation is in progress.

## Context

Native request repetition currently spans AnyLanguageModel provider implementations, RuntimeSystem recovery and AgentSessionOrchestrator completion recovery. This makes common request boundaries and effect-preserving recovery difficult to enforce consistently.

## Decision

The [unified native agent loop design](../../designs/native-agent-loop.md) proposes that AgentRuntime own scheduling. Provider adapters return one response without executable tools. Core continues to own access, approvals and product-specific completion policy through existing injected boundaries. Persisted session data determines model context; cached provider sessions are disposable.

## Consequences

Adapters and consumers migrate in phases. Unsupported providers remain legacy. Preserve typed completion, evidence, reconciliation, concurrency barriers, reasoning/continuation metadata and cache/usage behavior. New journal writers require compatible readers and a tested downgrade gate. External ACP loops remain external.

This proposal does not automatically change existing planning defaults or remove earlier safety/reliability contracts. Planning policy and stricter evidence freshness require their separate rollout described in the design.
