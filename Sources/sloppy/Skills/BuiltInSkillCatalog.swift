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
    static let modeAskID = "sloppy/mode-ask"
    static let modeBuildID = "sloppy/mode-build"
    static let modePlanID = "sloppy/mode-plan"
    static let modeDebugID = "sloppy/mode-debug"
    static let modeAutoID = "sloppy/mode-auto"

    static func all() -> [BuiltInSkillDefinition] {
        [
            modeSkill(for: .ask),
            modeSkill(for: .build),
            modeSkill(for: .plan),
            modeSkill(for: .debug),
            modeSkill(for: .auto),
            taskSpecWriter()
        ]
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

    private static func loadSkillMarkdown(repo: String, fallback: String) -> String {
        let relativePath = "Skills/\(repo)/SKILL.md"
        let candidates: [URL?] = [
            Bundle.module.url(
                forResource: "SKILL",
                withExtension: "md",
                subdirectory: "Skills/\(repo)"
            ),
            Bundle.module.resourceURL?
                .appendingPathComponent(relativePath),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Sources/sloppy/Resources")
                .appendingPathComponent(relativePath),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(relativePath)
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                return text
            }
        }

        return fallback
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
            Before meaningful edits, call `planning.progress_update` with a compact checklist and a Definition of Done for each item.
            Write tests for behavior changes, run them, fix failures, and build the project before finishing when working on a project.
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
            For substantial work, offer to capture the plan as a project task and use project task tools when the user asks to create, save, or track it.
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
            Do not mutate files unless the selected route permits it. If no route is a good fit, use the Ask route and answer directly or ask for the smallest clarification needed.
            """
        }
    }
}
