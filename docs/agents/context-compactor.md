# Context Compactor

Every AI model has a limited context window — a maximum amount of text it can consider at once. As a conversation grows longer, more and more of that window gets consumed by message history. Eventually, there's not enough space left for the model to give a meaningful response.

The Context Compactor is the subsystem that solves this automatically. It watches how full the context window is getting, and at the right moment it summarizes the existing conversation into a compact digest — preserving what matters while freeing up space for the conversation to continue.

## Why it matters

Without compaction, a long-running conversation would eventually hit the model's limit and stop working. The compactor prevents this by being proactive: it summarizes before things become critical, and it can compress more aggressively if the situation is urgent.

This is especially important for agents running long autonomous tasks, complex back-and-forth coding sessions, or channels that stay open for hours or days.

## How it works

After every message, the compactor checks how full the context is. Context utilization is estimated from the total length of the conversation history relative to the model's token budget. When a threshold is crossed, the compactor schedules a summarization job for that channel.

There are three threshold levels, each representing a different level of urgency:

| Level | Triggered at | What it does |
|---|---|---|
| Soft | 80% full | Mild summarization; compresses older parts of the history |
| Aggressive | 85% full | Stronger compression; keeps only the most important context |
| Emergency | 95% full | Maximum compression; preserves only the essentials |

Each level is triggered at most once per channel. If context jumps directly from 60% to 88%, only the aggressive job is scheduled — not both soft and aggressive.

## Deduplication and ordering

The compactor never runs the same level twice for the same channel at the same time. If a job is already active or queued for a given channel and level, new trigger events are silently dropped. This prevents redundant summarization when multiple messages arrive in quick succession near a threshold.

Jobs within a channel are always processed one at a time, in order. Multiple channels are handled independently and in parallel.

## Reliability

Summarization jobs can fail — for example, if the model call times out. The compactor retries failed jobs automatically, up to three times, with a short delay between each attempt. After three failures the job is dropped and the next natural threshold crossing will schedule a fresh one.

## What gets published

The compactor emits events to the internal event bus so you can observe its activity:

- **Threshold crossed** — fired when the compactor decides a level has been reached and a job has been created.
- **Summary applied** — fired when a compaction job completes successfully.

These events can be used by dashboards, webhooks, or monitoring integrations to track compaction activity.
