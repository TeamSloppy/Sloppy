# ADR 0004: AdaUI Product Shell and Feature Mapping

- Status: Accepted
- Date: 2026-03-24

## Context

The future client must be built with AdaUI, but the current local AdaUI snapshot does not provide several high-level controls required by the dashboard-style product shell. Local inspection shows basic building blocks such as `WindowGroup`, `@State`, layout stacks, gestures, `ScrollView`, and text rendering, but not ready-made tabs, text fields, lists, or high-level navigation.

## Decision

- Build the app as `pure AdaUI`.
- Implement the product shell and missing high-level controls inside the AdaUI ecosystem instead of falling back to UIKit/AppKit controls.
- Start with reusable app-level components:
  - `AppTabBar`
  - `SegmentedTabStrip`
  - `SidebarRail`
  - `ListView` patterns for cards/rows
  - `SplitPane`
- Add engine-level primitives where necessary:
  - focus routing
  - text input field foundation
  - keyboard-first interaction support
  - scroll stability improvements for long chat/task feeds

## Product Mapping

Root surfaces:
- `Overview`
- `Projects`
- `Agents`
- `Tasks`
- `Review`

Nested surfaces:
- project detail tabs for overview, tasks, channels, workers, files
- agent detail tabs for overview, chat, tasks, channels, config

Implementation order:
1. app shell and root navigation
2. read-only overview/projects/agents
3. interactive chat
4. task management details
5. code review diff and comments

## Consequences

Positive:
- The client becomes a real AdaUI proving ground
- Engine issues are surfaced early and fixed close to the product need
- The UI model stays consistent across platforms

Negative:
- v1 foundation work is heavier
- Text input, focus, and review UI carry extra risk compared to native Apple controls

## Non-Goals

- No UIKit/AppKit bridge for core product interactions in v1
- No side-by-side diff in the first review implementation
