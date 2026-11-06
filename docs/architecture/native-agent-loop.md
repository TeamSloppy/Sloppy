---
layout: doc
title: Native Agent Loop Architecture
---

# Native agent loop architecture

The current design is [Unified native agent loop](../designs/native-agent-loop.md). It replaces the earlier Russian draft at this URL with an English specification under the contributor workflow.

The proposed direction is one runtime-owned model/tool loop, canonical persisted context and explicit completion/recovery policies. Existing approvals, verification evidence, coordinator handoff, worker finalizers and unknown-effect reconciliation remain required.

See the proposed [ownership decision](adr/0008-unified-native-agent-loop.md) and [native execution guide](../guides/native-agent-execution.md) for delivery status and behavior. Migration stages are part of the design; an implementation plan follows approval. The design is not a claim that the unified engine is already available.

![Unified native agent loop](/design/native-agent-loop.svg)
