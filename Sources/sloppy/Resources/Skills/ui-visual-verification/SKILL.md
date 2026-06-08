---
name: ui-visual-verification
description: "Verify web and desktop UI changes with browser automation, screenshots, interaction checks, and visual comparison against expected behavior."
version: 1.0.0
author: Sloppy Team
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Development, UI, Browser, Visual-Verification, QA, Screenshots]
    related_skills: [mode-build, test-authoring, development-code-review]
---

# UI Visual Verification

Use this skill when work affects a user interface, visual layout, web page, desktop screen, interactive flow, accessibility state, or any user-visible behavior that cannot be confidently verified by unit tests alone.

This skill complements automated tests. It does not replace focused unit, integration, or acceptance tests when those are available.

## When to Use

Use visual verification for changes involving:

- web frontend UI, routing, navigation, forms, dashboards, charts, dialogs, or responsive layout;
- desktop app windows, panels, menus, toolbars, dialogs, notifications, or native controls;
- visual regressions, CSS/styling, spacing, colors, typography, icons, loading states, empty states, or error states;
- click/keyboard flows, drag/drop, focus handling, keyboard shortcuts, and disabled/enabled states;
- screenshots, generated previews, canvases, maps, media, or other visual surfaces.

Do not require browser or desktop visual verification for purely backend, CLI, data-model, or non-UI changes unless the user explicitly asks for it.

## Inputs to Establish

Before verification, identify:

- the target surface: web URL, local route, desktop app/window, or screen area;
- the expected user-visible behavior;
- the primary flows to exercise;
- required app startup command, environment, credentials, test account, or seed data;
- known constraints such as unavailable browser tools, missing display, blocked login, or external services.

Ask the user only when a required URL, credential, account, or expected flow is blocking. Otherwise proceed with the best available local verification.

## Web Verification Workflow

For web apps:

1. Start or reuse the app server when needed.
2. Open the target URL in the browser.
3. Wait for the page to settle enough for reliable observation.
4. Capture an initial screenshot.
5. Exercise the changed flow:
   - click relevant controls;
   - type representative input;
   - navigate primary routes;
   - submit forms where safe;
   - test loading, empty, validation, success, and error states when practical.
6. Capture screenshots after meaningful states or transitions.
7. Compare observed UI against the expected behavior and the change request.
8. Record defects with reproduction steps, observed result, expected result, and screenshot references when available.

Prefer browser automation tools when available, such as opening pages, clicking selectors, typing into fields, navigating URLs, and capturing screenshots. If browser automation is unavailable, report that limitation and use screenshots, logs, tests, or manual inspection as appropriate.

## Desktop Verification Workflow

For desktop apps:

1. Build and launch the app when practical.
2. Bring the relevant window or screen state into view.
3. Capture a full-screen screenshot or the most targeted screenshot available.
4. Exercise the changed flow using safe clicks, typing, menu actions, or keyboard shortcuts.
5. Capture screenshots after meaningful states or transitions.
6. Inspect the screenshots for layout, visibility, state, and regressions.
7. Record defects with reproduction steps, observed result, expected result, and screenshot references when available.

If the app cannot be launched, the display is unavailable, or interactive tools are missing, state the blocker and perform the strongest remaining validation.

## Visual Review Checklist

- [ ] The changed UI surface is reachable.
- [ ] Primary flow works from the user's perspective.
- [ ] Interactive controls respond correctly.
- [ ] Loading, empty, error, disabled, and success states are acceptable where relevant.
- [ ] Layout is not obviously broken at the tested viewport/window size.
- [ ] Text, icons, spacing, and alignment match the expected design or existing style.
- [ ] Keyboard/focus behavior is acceptable for changed controls where relevant.
- [ ] Screenshots or observations were captured for important states.
- [ ] Any defects include reproduction steps and expected vs observed behavior.

## Reporting Format

When reporting UI verification, use:

```md
## UI Verification

Surface:
- <URL, route, app window, or screen>

Flows checked:
- <flow/state> — <pass/fail/not checked>

Screenshots:
- <path or description> — <state captured>

Findings:
- <none or issue list with steps, expected, observed>

Limitations:
- <credentials unavailable, app failed to launch, no browser/display tools, or none>
```

## Constraints

- Do not fabricate screenshots, clicks, observations, or test results.
- Do not perform destructive actions in a live app unless the user explicitly permits them.
- Do not enter secrets into untrusted pages. Ask for safe test credentials or a local test environment when needed.
- Keep visual verification scoped to the changed UI and highest-risk adjacent flows unless the user asks for a broader QA pass.
- Prefer concise findings with evidence over long narrative descriptions.
