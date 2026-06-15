---
name: deep-research
description: Runs configurable multi-round research with compare, review, and explore modes, visible progress, source collection, and final sourced answers.
userInvocable: true
allowedTools:
  - web.search
  - web.fetch
  - planning.progress_update
  - runtime.exec
---

# Deep Research

Use this skill when the user asks for `/deepresearch` or explicitly requests deep research.

Configuration is supplied as:
- `mode`: `compare`, `review`, or `explore`
- `rounds`: integer from 1 to 8
- user request: the research prompt

Treat each round as one search plus synthesis cycle:
1. plan the round's search angle
2. search with `web.search`
3. fetch/read the most relevant sources with `web.fetch`
4. update visible progress with `planning.progress_update`
5. synthesize what changed before the next round

Mode behavior:
- `compare`: compare alternatives, criteria, tradeoffs, and evidence.
- `review`: evaluate one subject, claim, product, document, or proposal with strengths, risks, and verdict.
- `explore`: map a topic, identify themes, unknowns, and promising follow-up directions.

The final answer must include:
- direct answer
- mode-specific findings
- sources with links or source identifiers
- what was verified
- what remains uncertain

Do not decide progress, completion, or source quality by matching assistant prose. Use tool results, fetched source content, and explicit progress updates.
