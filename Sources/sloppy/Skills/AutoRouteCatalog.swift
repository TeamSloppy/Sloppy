import Foundation
import Protocols

enum AutoRouteCatalog {
    static func defaultMarkdown() -> String {
        markdown(installedSkills: [])
    }

    static func markdown(installedSkills: [InstalledSkill]) -> String {
        var entries = builtInEntries()
        entries.append(contentsOf: installedSkillEntries(installedSkills))

        return """
        [Auto route catalog]
        \(entries.joined(separator: "\n"))
        """
    }

    private static func builtInEntries() -> [String] {
        [
            "- route: mode-ask | skill: `sloppy/mode-ask` | use_when: The user asks a question, requests explanation, wants current information, or needs a non-mutating answer.",
            "- route: mode-plan | skill: `sloppy/mode-plan` | use_when: The user asks for a plan, design, investigation path, implementation breakdown, or wants to decide before code changes.",
            "- route: mode-debug | skill: `sloppy/mode-debug` | use_when: The user reports a bug, failing test, regression, runtime error, broken behavior, or asks to investigate evidence.",
            "- route: mode-build | skill: `sloppy/mode-build` | use_when: The user asks to implement, edit, create, refactor, wire, fix with code changes, or execute an approved plan.",
            "- route: skill:sloppy/task-spec-writer | skill: `sloppy/task-spec-writer` | use_when: The user explicitly asks to create, save, track, or formalize work as a project task/spec."
        ]
    }

    private static func installedSkillEntries(_ skills: [InstalledSkill]) -> [String] {
        skills
            .filter { skill in
                guard !builtInSkillIDs.contains(skill.id) else {
                    return false
                }
                return normalized(skill.autoRoute) != nil
            }
            .sorted { lhs, rhs in
                lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
            .compactMap { skill in
                guard let autoRoute = normalized(skill.autoRoute) else {
                    return nil
                }
                var parts = [
                    "route: skill:\(skill.id)",
                    "skill: `\(skill.id)`",
                    "use_when: \(autoRoute)"
                ]
                if let description = normalized(skill.description) {
                    parts.append("description: \(description)")
                }
                return "- " + parts.joined(separator: " | ")
            }
    }

    private static let builtInSkillIDs: Set<String> = [
        BuiltInSkillCatalog.modeAskID,
        BuiltInSkillCatalog.modeBuildID,
        BuiltInSkillCatalog.modePlanID,
        BuiltInSkillCatalog.modeDebugID,
        BuiltInSkillCatalog.modeAutoID,
        BuiltInSkillCatalog.taskSpecWriterID
    ]

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
