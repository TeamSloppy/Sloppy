# TUI Project Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/projects` to switch workspaces inside one TUI instance on the active backend.

**Architecture:** Reuse the existing TUI picker and backend abstraction. Add a project picker kind, command registration, a pure mapper for project picker rows, and a current-backend project switch helper that resets project-local state while preserving per-project session tracking.

**Tech Stack:** Swift 6.2, Swift Testing, existing `SloppyTUIBackend`, `SloppyTUIPicker`, and TUI state store.

---

### Task 1: Command Registration And Picker Model

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUIModels.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen.swift`
- Modify: `Tests/sloppyTests/SloppyTUICommandsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests that assert `/projects` and `/project` are recognized and that project-scoped tracked-session keys stay separate:

```swift
@Test
@MainActor
func projectsCommandIsRegisteredInTUI() {
    #expect(SloppyTUIScreen.handledSlashCommandNames.contains("projects"))
    #expect(SloppyTUIScreen.handledSlashCommandNames.contains("project"))
    #expect(SloppyTUIScreen.baseSlashCommands.contains { $0.name == "projects" })
}

@Test
func tuiStateKeepsTrackedSessionsProjectScoped() {
    #expect(SloppyTUIStateStore.trackedSessionsKey(projectId: "alpha") == "project:alpha")
    #expect(SloppyTUIStateStore.trackedSessionsKey(projectId: "beta") == "project:beta")
    #expect(SloppyTUIStateStore.trackedSessionsKey(projectId: "alpha") != SloppyTUIStateStore.trackedSessionsKey(projectId: "beta"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SloppyTUICommandsTests/projectsCommandIsRegisteredInTUI`

Expected: FAIL because `projects` and `project` are not registered.

- [ ] **Step 3: Add picker kind and command registration**

Add `case project` to `SloppyTUIPickerKind`.

Add to `baseSlashCommands`:

```swift
SloppyTUISlashCommand("projects", "Switch project workspace"),
```

Add to `handledSlashCommandNames`:

```swift
"projects",
"project",
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SloppyTUICommandsTests/projectsCommandIsRegisteredInTUI`

Expected: PASS.

### Task 2: Project Picker Rows

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUIModels.swift`
- Modify: `Tests/sloppyTests/SloppyTUICommandsTests.swift`

- [ ] **Step 1: Write the failing test**

Add a pure helper test:

```swift
@Test
func projectPickerItemsSortNewestFirstAndMarkCurrent() {
    let older = ProjectRecord(
        id: "older",
        name: "Older",
        description: "",
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let newer = ProjectRecord(
        id: "newer",
        name: "Newer",
        description: "",
        updatedAt: Date(timeIntervalSince1970: 20)
    )

    let items = SloppyTUIProjectPicker.items(for: [older, newer], currentProjectID: "older")

    #expect(items.map(\.value) == ["newer", "older"])
    #expect(items.first?.label == "Newer")
    #expect(items.last?.isCurrent == true)
    #expect(items.last?.searchHaystack.contains("older") == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SloppyTUICommandsTests/projectPickerItemsSortNewestFirstAndMarkCurrent`

Expected: FAIL because `SloppyTUIProjectPicker` does not exist.

- [ ] **Step 3: Implement the pure mapper**

Add this helper to `SloppyTUIModels.swift`:

```swift
enum SloppyTUIProjectPicker {
    static func items(for projects: [ProjectRecord], currentProjectID: String) -> [SloppyTUIPickerItem] {
        projects
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { project in
                SloppyTUIPickerItem(
                    value: project.id,
                    label: project.name,
                    description: "\(project.id) · \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))",
                    isCurrent: project.id == currentProjectID
                )
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SloppyTUICommandsTests/projectPickerItemsSortNewestFirstAndMarkCurrent`

Expected: PASS.

### Task 3: Project Command Flow

**Files:**
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen+Commands.swift`
- Modify: `Sources/sloppy/TUI/SloppyTUIScreen+Features.swift`

- [ ] **Step 1: Route the command**

In `handleCommand(_:)`, add:

```swift
case "projects", "project":
    await showProjectPicker()
```

- [ ] **Step 2: Implement project picker display**

Add `showProjectPicker()` near the remote picker helpers:

```swift
func showProjectPicker() async {
    refreshStaticChrome(statusLine: "loading projects from \(service.displayName)...")
    do {
        let projects = try await service.listProjects()
        guard !projects.isEmpty else {
            appendLocalCard("No projects available on `\(service.displayName)`.", autoDismissAfter: 8)
            return
        }
        let items = SloppyTUIProjectPicker.items(for: projects, currentProjectID: project.id)
        activePicker = SloppyTUIPicker(
            kind: .project,
            title: "Select project",
            items: items,
            selectedIndex: items.firstIndex(where: \.isCurrent) ?? 0,
            allItems: items,
            supportsSearch: true
        )
        refreshStaticChrome(statusLine: "choose project, Enter to switch workspace, Esc to cancel")
    } catch {
        appendLocalCard("Could not load projects from `\(service.displayName)`: \(String(describing: error))")
    }
}
```

- [ ] **Step 3: Apply project picker selection**

Add to `applyPickerItem(_:kind:)`:

```swift
case .project:
    await switchProject(item.value)
```

- [ ] **Step 4: Implement project switching**

Add `switchProject(_:)` near `switchSession(_:)`:

```swift
func switchProject(_ projectID: String) async {
    guard projectID != project.id else {
        activePicker = nil
        appendLocalCard("Already in project `\(project.name)`.", autoDismissAfter: 6)
        return
    }
    await switchBackend(service, projectID: projectID, statusPrefix: "\(service.displayName) project")
}
```

- [ ] **Step 5: Run narrow tests**

Run: `swift test --filter SloppyTUICommandsTests`

Expected: PASS.

### Task 4: Verification

**Files:**
- No additional source files.

- [ ] **Step 1: Build TUI-bearing product**

Run: `swift build --product sloppy`

Expected: PASS.

- [ ] **Step 2: Run relevant TUI tests**

Run: `swift test --filter SloppyTUI`

Expected: PASS.

## Self-Review

The plan covers command registration, picker UI model, project selection, project-scoped session continuity, and verification. No new Core API is needed. Cross-instance project aggregation remains out of scope for v1.
