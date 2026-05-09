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

    static func all() -> [BuiltInSkillDefinition] {
        [
            taskSpecWriter()
        ]
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

    private static func loadTaskSpecWriterMarkdown() -> String {
        let relativePath = "Skills/task-spec-writer/SKILL.md"
        let candidates: [URL?] = [
            Bundle.module.url(
                forResource: "SKILL",
                withExtension: "md",
                subdirectory: "Skills/task-spec-writer"
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

        return """
        ---
        name: task-spec-writer
        description: Automatically turns vague work into structured project task briefs with technical requirements, Definition of Done, verification, RFC/ADR expectations, memory follow-up, and clean handoff notes.
        userInvocable: false
        ---

        # Task Spec Writer

        Write project tasks as structured briefs with Goal, Context, In Scope, Out of Scope, Technical Requirements, Implementation Notes, Definition of Done, Tests / Verification, RFC / ADR, and Memory / Follow-up.
        """
    }
}
