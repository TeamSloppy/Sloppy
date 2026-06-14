import Foundation
import Protocols

struct BuiltInSkillDefinition: Sendable {
    var owner: String
    var repo: String
    var name: String
    var description: String
    var userInvocable: Bool
    var allowedTools: [String]
    var files: [String: String]
}

enum BuiltInSkillCatalog {
    static let taskSpecWriterID = "sloppy/task-spec-writer"
    static let kanbanTaskManagerID = "sloppy/kanban-task-manager"
    static let modeAskID = "sloppy/mode-ask"
    static let modeBuildID = "sloppy/mode-build"
    static let modePlanID = "sloppy/mode-plan"
    static let modeDebugID = "sloppy/mode-debug"
    static let modeAutoID = "sloppy/mode-auto"
    static let workflowID = "sloppy/workflow"

    static func all() -> [BuiltInSkillDefinition] {
        [
            modeSkill(for: .ask),
            modeSkill(for: .build),
            modeSkill(for: .plan),
            modeSkill(for: .debug),
            modeSkill(for: .auto),
            kanbanTaskManager(),
            taskSpecWriter(),
            workflow()
        ] + bundledResourceSkills()
    }

    static func modeSkillMarkdown(for mode: AgentChatMode) -> String {
        loadSkillMarkdown(
            repo: modeSkillRepo(for: mode),
            fallback: fallbackModeSkillMarkdown(for: mode)
        )
    }

    static func modeSkillRepo(for mode: AgentChatMode) -> String {
        switch mode {
        case .ask:
            return "mode-ask"
        case .build:
            return "mode-build"
        case .plan:
            return "mode-plan"
        case .debug:
            return "mode-debug"
        case .auto:
            return "mode-auto"
        }
    }

    static func taskSpecWriter() -> BuiltInSkillDefinition {
        BuiltInSkillDefinition(
            owner: "sloppy",
            repo: "task-spec-writer",
            name: "task-spec-writer",
            description: "Writes structured project task briefs with technical requirements, DoD, verification, RFC/ADR, memory, and handoff expectations.",
            userInvocable: false,
            allowedTools: [
                "project.task_list",
                "project.task_create",
                "project.task_update",
                "memory.save"
            ],
            files: [
                "SKILL.md": loadTaskSpecWriterMarkdown()
            ]
        )
    }

    static func kanbanTaskManager() -> BuiltInSkillDefinition {
        BuiltInSkillDefinition(
            owner: "sloppy",
            repo: "kanban-task-manager",
            name: "kanban-task-manager",
            description: "Creates and maintains project-board tasks with correct dedupe, umbrella/root linking, dependencies, tags, authors, assignments, and autopilot queue placement.",
            userInvocable: false,
            allowedTools: [
                "project.current",
                "project.task_list",
                "project.task_get",
                "project.task_create",
                "project.task_update",
                "project.task_clarification_create",
                "memory.save"
            ],
            files: [
                "SKILL.md": loadKanbanTaskManagerMarkdown()
            ]
        )
    }

    static func workflow() -> BuiltInSkillDefinition {
        BuiltInSkillDefinition(
            owner: "sloppy",
            repo: "workflow",
            name: "workflow",
            description: "Creates explicit visual workflow plans for project work, links agent steps to typed runtime state, and returns Dashboard workflow URLs.",
            userInvocable: true,
            allowedTools: [
                "project.current",
                "project.task_list",
                "project.task_get",
                "project.workflow"
            ],
            files: [
                "SKILL.md": loadWorkflowMarkdown()
            ]
        )
    }

    static func modeSkill(for mode: AgentChatMode) -> BuiltInSkillDefinition {
        let repo = modeSkillRepo(for: mode)
        return BuiltInSkillDefinition(
            owner: "sloppy",
            repo: repo,
            name: repo,
            description: modeSkillDescription(for: mode),
            userInvocable: false,
            allowedTools: modeSkillAllowedTools(for: mode),
            files: [
                "SKILL.md": modeSkillMarkdown(for: mode)
            ]
        )
    }

    private static func loadTaskSpecWriterMarkdown() -> String {
        loadSkillMarkdown(
            repo: "task-spec-writer",
            fallback: """
            ---
            name: task-spec-writer
            description: Automatically turns vague work into structured project task briefs with technical requirements, Definition of Done, verification, RFC/ADR expectations, memory follow-up, and clean handoff notes.
            userInvocable: false
            ---

            # Task Spec Writer

            Write project tasks as structured briefs with Goal, Context, In Scope, Out of Scope, Technical Requirements, Implementation Notes, Definition of Done, Tests / Verification, RFC / ADR, and Memory / Follow-up.
            """
        )
    }

    private static func loadKanbanTaskManagerMarkdown() -> String {
        loadSkillMarkdown(
            repo: "kanban-task-manager",
            fallback: """
            ---
            name: kanban-task-manager
            description: Creates and maintains project-board tasks with correct dedupe, umbrella/root linking, dependencies, tags, authors, assignments, and autopilot queue placement.
            userInvocable: false
            ---

            # Kanban Task Manager

            Use this skill whenever you create, save, track, decompose, link, assign, retag, or enqueue work as project-board tasks. Inspect the current project and task list first, avoid duplicates, create umbrella/root tasks for multi-step work, use parent/dependency fields for the graph, preserve useful tags and assignments, and put autopilot-eligible root tasks in backlog with the configured autopilot tag and trusted author.
            """
        )
    }

    private static func loadWorkflowMarkdown() -> String {
        loadSkillMarkdown(
            repo: "workflow",
            fallback: """
            ---
            name: workflow
            description: Create visual workflow plans for project work, with typed graph nodes, links to agent execution, and Dashboard URLs.
            userInvocable: true
            allowedTools:
              - project.current
              - project.task_list
              - project.task_get
              - project.workflow
            ---

            # Workflow

            Use this skill when the user explicitly asks for a workflow, visual plan, workflow-mode execution, or when the task benefits from a visible step graph.

            When active:
            - inspect project and task context first
            - create a draft workflow proposal before substantial work
            - model work as lanes, nodes, and edges
            - use `project.workflow` for workflow state; do not write workflow files directly
            - link `agent_step` nodes to agent/session/delegated-task IDs through typed metadata
            - update workflow state from runtime events and tool results, not model-output text
            - after creating or completing a workflow, provide the Dashboard workflow URL

            Do not create workflows outside this skill.
            """
        )
    }

    private static func loadSkillMarkdown(repo: String, fallback: String) -> String {
        for candidate in skillMarkdownURLs(repo: repo) {
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                return text
            }
        }

        return fallback
    }

    private static func bundledResourceSkills() -> [BuiltInSkillDefinition] {
        resourceSkillDefinitions()
    }

    static func resourceSkillDefinitions(
        fileManager: FileManager = .default,
        executablePath: String? = CommandLine.arguments.first,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) -> [BuiltInSkillDefinition] {
        var definitionsByID: [String: BuiltInSkillDefinition] = [:]
        for root in skillResourceRootURLs(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath,
            sourceFilePath: sourceFilePath
        ) {
            for definition in bundledResourceSkills(in: root) {
                let id = "\(definition.owner)/\(definition.repo)"
                if definitionsByID[id] == nil {
                    definitionsByID[id] = definition
                }
            }
        }
        return definitionsByID.values.sorted {
            $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending
        }
    }

    private static func bundledResourceSkills(in root: URL) -> [BuiltInSkillDefinition] {
        let builtInRepos = Set(["task-spec-writer", "kanban-task-manager", "workflow"] + AgentChatMode.allCases.map { modeSkillRepo(for: $0) })
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var definitionsByRepo: [String: BuiltInSkillDefinition] = [:]
        for directory in children.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true
            else { continue }

            let repo = skillIDComponent(from: directory.lastPathComponent)
            guard !builtInRepos.contains(repo), definitionsByRepo[repo] == nil else { continue }

            let skillFile = directory.appendingPathComponent("SKILL.md")
            guard let markdown = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }
            let frontmatter = SkillsGitHubClient.parseFrontmatter(from: markdown)
            let name = normalizedFrontmatterValue(frontmatter?.name) ?? repo
            let description = normalizedFrontmatterValue(frontmatter?.description) ?? "Bundled skill from Sloppy resources."
            let userInvocable = frontmatter?.userInvocable ?? true
            let allowedTools = frontmatter?.allowedTools ?? []

            definitionsByRepo[repo] = BuiltInSkillDefinition(
                owner: "bundled",
                repo: repo,
                name: name,
                description: description,
                userInvocable: userInvocable,
                allowedTools: allowedTools,
                files: collectSkillFiles(in: directory)
            )
        }

        return definitionsByRepo.values.sorted {
            $0.repo.localizedCaseInsensitiveCompare($1.repo) == .orderedAscending
        }
    }

    private static func collectSkillFiles(in directory: URL) -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return [:]
        }

        var files: [String: String] = [:]
        let rootPath = directory.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let content = try? String(contentsOf: fileURL, encoding: .utf8)
            else { continue }

            let relative = fileURL.standardizedFileURL.path
                .dropFirst(rootPath.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard isSafeSkillRelativePath(relative) else { continue }
            files[relative] = content
        }
        return files
    }

    private static func skillMarkdownURLs(
        repo: String,
        fileManager: FileManager = .default,
        executablePath: String? = CommandLine.arguments.first,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) -> [URL] {
        skillResourceRootURLs(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath,
            sourceFilePath: sourceFilePath
        ).map {
            $0.appendingPathComponent(repo).appendingPathComponent("SKILL.md")
        }
    }

    private static func skillResourceRootURLs(
        fileManager: FileManager,
        executablePath: String?,
        currentDirectoryPath: String,
        sourceFilePath: String
    ) -> [URL] {
        var candidates: [URL] = []

        for directoryURL in executableDirectories(
            fileManager: fileManager,
            executablePath: executablePath,
            currentDirectoryPath: currentDirectoryPath
        ) {
            candidates.append(directoryURL.appendingPathComponent("Skills", isDirectory: true))
            candidates.append(
                directoryURL
                    .appendingPathComponent("Sloppy_sloppy.bundle", isDirectory: true)
                    .appendingPathComponent("Skills", isDirectory: true)
            )
            candidates.append(
                directoryURL
                    .appendingPathComponent("Sloppy_sloppy.resources", isDirectory: true)
                    .appendingPathComponent("Skills", isDirectory: true)
            )
            candidates.append(
                directoryURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("share/sloppy/Skills", isDirectory: true)
            )
        }

        candidates.append(
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Sources/sloppy/Resources", isDirectory: true)
                .appendingPathComponent("Skills", isDirectory: true)
        )
        candidates.append(
            URL(fileURLWithPath: sourceFilePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Skills", isDirectory: true)
        )

        var seen = Set<String>()
        return candidates.map(\.standardizedFileURL).filter { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return false
            }
            return seen.insert(url.path).inserted
        }
    }

    private static func executableDirectories(
        fileManager: FileManager,
        executablePath: String?,
        currentDirectoryPath: String
    ) -> [URL] {
        guard let executablePath, !executablePath.isEmpty else {
            return []
        }

        let currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        let rawExecutableURL: URL
        if executablePath.hasPrefix("/") {
            rawExecutableURL = URL(fileURLWithPath: executablePath)
        } else {
            rawExecutableURL = URL(fileURLWithPath: executablePath, relativeTo: currentDirectoryURL)
        }

        var directories: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let directoryURL = url.standardizedFileURL.deletingLastPathComponent()
            guard seenPaths.insert(directoryURL.path).inserted else { return }
            directories.append(directoryURL)
        }

        append(rawExecutableURL)
        append(rawExecutableURL.resolvingSymlinksInPath())

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: rawExecutableURL.path) {
            let destinationURL: URL
            if destination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: destination)
            } else {
                destinationURL = rawExecutableURL.deletingLastPathComponent().appendingPathComponent(destination)
            }
            append(destinationURL)
        }

        return directories
    }

    private static func isSafeSkillRelativePath(_ relative: String) -> Bool {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func normalizedFrontmatterValue(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func skillIDComponent(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        var result = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "skill" : result
    }

    private static func modeSkillDescription(for mode: AgentChatMode) -> String {
        switch mode {
        case .ask:
            return "Runtime instructions for Ask mode: answer directly without code mutation."
        case .build:
            return "Runtime instructions for Build mode: implement changes, keep progress visible, test, and verify."
        case .plan:
            return "Runtime instructions for Plan mode: produce implementation or investigation plans without code mutation."
        case .debug:
            return "Runtime instructions for Debug mode: investigate with hypotheses, instrumentation, logs, and user feedback."
        case .auto:
            return "Runtime instructions for Auto mode: select the best behavior route from the route catalog, then follow that route."
        }
    }

    private static func modeSkillAllowedTools(for mode: AgentChatMode) -> [String] {
        // Runtime modes are behavioral instructions, not tool capability filters.
        // Keep this empty so mode metadata does not look like the whole tool surface;
        // actual access is governed by the agent tool policy, guardrails, approvals, and sandbox.
        switch mode {
        case .ask, .build, .plan, .debug, .auto:
            return []
        }
    }

    private static func fallbackModeSkillMarkdown(for mode: AgentChatMode) -> String {
        switch mode {
        case .ask:
            return """
            ---
            name: mode-ask
            description: Runtime instructions for Ask mode.
            userInvocable: false
            ---

            # Ask Mode

            Answer the user's question directly. Use `web.search` and `web.fetch` when current or external web information is needed. Do not edit files, run mutating commands, or make code changes unless the authoritative runtime mode is build or debug for this turn.
            """
        case .build:
            return """
            ---
            name: mode-build
            description: Runtime instructions for Build mode.
            userInvocable: false
            ---

            # Build Mode

            Implement the requested change by writing code, editing files, and running the smallest relevant verification.
            If the request references a project task or follows a Plan-mode task handoff, fetch the task details first and preserve acceptance criteria and constraints.
            Every build-mode turn that performs implementation, edits, refactors, fixes, or verification must include a visible working checklist.
            Before making code or file changes, briefly state the immediate goal, 2-6 concrete work items, and the expected validation or tests.
            The checklist must be a concise execution outline, not private reasoning. Do not expose hidden chain-of-thought.
            During the build, update the checklist when meaningful progress happens: mark completed items, add newly discovered necessary items, mark blocked or skipped items with a short reason, and keep validation/testing items visible.
            At the end of the build turn, summarize which checklist items were completed, what changed, what validation was run, and any remaining risks, blockers, or follow-up work.
            Prefer concise checklist updates over long explanations.
            Before meaningful edits, call `planning.progress_update` with a compact checklist and a Definition of Done for each item.
            Write tests for behavior changes, run them, fix failures, and build the project before finishing when working on a project.
            When build work affects a web UI, desktop UI, visual layout, user flow, interactive behavior, or other user-visible screen state, follow the `ui-visual-verification` skill as part of verification.
            For web UI changes, open the relevant page in a browser when possible, interact with the changed flow, capture screenshots for important states, and compare the observed behavior against the expected result.
            For desktop UI changes, launch or focus the app when practical, capture the screen or relevant window state, exercise the changed interaction, and inspect screenshots for regressions.
            If browser, display, app launch, credentials, or test data are unavailable, state the limitation and perform the strongest remaining validation.
            Do not fabricate visual observations, screenshots, clicks, or results.
            Ask only when a blocking requirement is ambiguous.
            """
        case .plan:
            return """
            ---
            name: mode-plan
            description: Runtime instructions for Plan mode.
            userInvocable: false
            ---

            # Plan Mode

            Produce a concise implementation or investigation plan with enough detail for a later Build-mode turn to execute without losing context.
            The final answer is saved by Sloppy as `PLAN_NAME.md` and rendered into a web page; safe raw HTML tags and attributes may be used in markdown, but scripts, event handlers, remote executable embeds, and `javascript:` links are not allowed.
            For substantial work, offer to capture the plan as a project task. When the user asks to create, save, track, decompose, link, update, or enqueue tasks, load and follow built-in skill `sloppy/kanban-task-manager`.
            Do not edit files, run code-changing commands, or make irreversible non-task changes unless the authoritative runtime mode is build or debug for this turn.
            Use `web.search` and `web.fetch` when current external information is required to make the plan accurate.
            Use `planning.request_input` after read-only inspection when an important user decision is needed before a correct plan can be written; ask 1-3 structured questions with 2-4 meaningful options each, then stop and wait.
            """
        case .debug:
            return """
            ---
            name: mode-debug
            description: Runtime instructions for Debug mode.
            userInvocable: false
            ---

            # Debug Mode

            Improve the existing debug session in a hypothesis-driven loop.
            Add focused diagnostic logging or instrumentation, wrap temporary blocks with `// #region agent debug` and `// #endregion`, and write NDJSON logs under `.sloppy/debug/debug-<shortSessionId>.log`.
            Use `planning.request_input` to pause for Proceed, Bug is repeated, or Mark as fixed, then use logs to classify hypotheses as CONFIRMED, REJECTED, or INCONCLUSIVE.
            """
        case .auto:
            return """
            ---
            name: mode-auto
            description: Runtime instructions for Auto mode.
            userInvocable: false
            ---

            # Auto Mode

            Choose one route from the Auto route catalog before acting, then follow that route's referenced mode or skill instructions in the same turn.
            Before following the selected route, call `planning.select_route` with the exact selected route id, such as `mode-plan`, `mode-build`, `mode-debug`, `mode-ask`, or `skill:<skill-id>`.
            Do not mutate files unless the selected route permits it. If no route is a good fit, use the Ask route and answer directly or ask for the smallest clarification needed.
            """
        }
    }
}
