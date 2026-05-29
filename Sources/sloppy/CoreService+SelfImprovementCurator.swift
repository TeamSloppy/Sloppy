import Foundation
import Protocols

// MARK: - Weekly self-improvement curator

extension CoreService {
    struct SelfImprovementCuratorProjectResult: Sendable, Equatable {
        var projectID: String
        var proposalCount: Int
        var duplicateGroupCount: Int
        var proposalTasksUpdated: Int
        var patchPlanTaskID: String?
        var patchPlanCreated: Bool
        var patchPlanUpdated: Bool
    }

    struct SelfImprovementCuratorResult: Sendable, Equatable {
        var projectsReviewed: Int
        var proposalsReviewed: Int
        var duplicateGroups: Int
        var proposalTasksUpdated: Int
        var patchPlanTasksCreated: Int
        var patchPlanTasksUpdated: Int
        var projectResults: [SelfImprovementCuratorProjectResult]
    }

    private struct SelfImprovementCuratorProposal {
        var projectID: String
        var projectName: String
        var task: ProjectTask
        var groupKey: String
        var subsystem: String
        var classification: String?
    }

    func runScheduledSelfImprovementCurator(reason: String) async -> SelfImprovementCuratorResult {
        await waitForStartup(dispatchReadyTasks: false)
        let projects = await store.listProjects()
        var results: [SelfImprovementCuratorProjectResult] = []

        for project in projects {
            let result = await runSelfImprovementCurator(projectID: project.id, reason: reason)
            if result.proposalCount > 0 {
                results.append(result)
            }
        }

        return SelfImprovementCuratorResult(
            projectsReviewed: results.count,
            proposalsReviewed: results.reduce(0) { $0 + $1.proposalCount },
            duplicateGroups: results.reduce(0) { $0 + $1.duplicateGroupCount },
            proposalTasksUpdated: results.reduce(0) { $0 + $1.proposalTasksUpdated },
            patchPlanTasksCreated: results.filter(\.patchPlanCreated).count,
            patchPlanTasksUpdated: results.filter(\.patchPlanUpdated).count,
            projectResults: results
        )
    }

    func runSelfImprovementCurator(projectID: String, reason: String) async -> SelfImprovementCuratorProjectResult {
        guard let normalizedProjectID = normalizedProjectID(projectID),
              let project = await store.project(id: normalizedProjectID)
        else {
            return SelfImprovementCuratorProjectResult(
                projectID: projectID,
                proposalCount: 0,
                duplicateGroupCount: 0,
                proposalTasksUpdated: 0,
                patchPlanTaskID: nil,
                patchPlanCreated: false,
                patchPlanUpdated: false
            )
        }

        let proposals = Self.selfImprovementCuratorProposals(in: project)
        guard !proposals.isEmpty else {
            return SelfImprovementCuratorProjectResult(
                projectID: normalizedProjectID,
                proposalCount: 0,
                duplicateGroupCount: 0,
                proposalTasksUpdated: 0,
                patchPlanTaskID: nil,
                patchPlanCreated: false,
                patchPlanUpdated: false
            )
        }

        let grouped = Dictionary(grouping: proposals) { $0.groupKey }
        let duplicateGroups = grouped.values
            .filter { $0.count > 1 }
            .map { group in Self.sortedSelfImprovementCuratorGroup(group) }
            .sorted { lhs, rhs in
                (lhs.first?.groupKey ?? "") < (rhs.first?.groupKey ?? "")
            }

        var proposalTasksUpdated = 0
        for group in duplicateGroups {
            let canonical = group[0]
            for proposal in group {
                let updatedDescription = Self.descriptionByReplacingCuratorDuplicateSection(
                    proposal.task.description,
                    group: group,
                    canonical: canonical,
                    reason: reason
                )
                guard updatedDescription != proposal.task.description else {
                    continue
                }
                do {
                    _ = try await updateProjectTask(
                        projectID: normalizedProjectID,
                        taskID: proposal.task.id,
                        request: ProjectTaskUpdateRequest(
                            description: updatedDescription,
                            changedBy: "system:self-improvement-curator"
                        )
                    )
                    proposalTasksUpdated += 1
                } catch {
                    logger.warning(
                        "self_improvement.curator.proposal_update_failed",
                        metadata: [
                            "project_id": .string(normalizedProjectID),
                            "task_id": .string(proposal.task.id),
                            "error": .string(error.localizedDescription),
                        ]
                    )
                }
            }
        }

        let refreshedProject = await store.project(id: normalizedProjectID) ?? project
        let refreshedProposals = Self.selfImprovementCuratorProposals(in: refreshedProject)
        let refreshedGroups = Dictionary(grouping: refreshedProposals) { $0.groupKey }
        let patchPlanDescription = Self.selfImprovementCuratorPatchPlanDescription(
            project: refreshedProject,
            proposals: refreshedProposals,
            groupedProposals: refreshedGroups,
            reason: reason
        )

        let patchPlanTask = Self.selfImprovementCuratorPatchPlanTask(in: refreshedProject)
        let patchPlanTaskID: String?
        var patchPlanCreated = false
        var patchPlanUpdated = false
        if let patchPlanTask {
            patchPlanTaskID = patchPlanTask.id
            if patchPlanTask.description != patchPlanDescription {
                do {
                    _ = try await updateProjectTask(
                        projectID: normalizedProjectID,
                        taskID: patchPlanTask.id,
                        request: ProjectTaskUpdateRequest(
                            description: patchPlanDescription,
                            status: ProjectTaskStatus.pendingApproval.rawValue,
                            kind: .planning,
                            tags: Self.selfImprovementCuratorPatchPlanTags,
                            changedBy: "system:self-improvement-curator"
                        )
                    )
                    patchPlanUpdated = true
                    appendTaskLifecycleLog(
                        projectID: normalizedProjectID,
                        taskID: patchPlanTask.id,
                        stage: "curator_updated",
                        channelID: nil,
                        workerID: nil,
                        message: "Self-improvement curator refreshed patch plan.",
                        actorID: "system:self-improvement-curator"
                    )
                } catch {
                    logger.warning(
                        "self_improvement.curator.patch_plan_update_failed",
                        metadata: ["project_id": .string(normalizedProjectID), "error": .string(error.localizedDescription)]
                    )
                }
            }
        } else {
            do {
                let updated = try await createProjectTask(
                    projectID: normalizedProjectID,
                    request: ProjectTaskCreateRequest(
                        title: Self.selfImprovementCuratorPatchPlanTitle(project: refreshedProject),
                        description: patchPlanDescription,
                        priority: "medium",
                        status: ProjectTaskStatus.pendingApproval.rawValue,
                        kind: .planning,
                        tags: Self.selfImprovementCuratorPatchPlanTags,
                        changedBy: "system:self-improvement-curator"
                    )
                )
                let created = Self.selfImprovementCuratorPatchPlanTask(in: updated)
                patchPlanTaskID = created?.id
                patchPlanCreated = created != nil
                if let created {
                    appendTaskLifecycleLog(
                        projectID: normalizedProjectID,
                        taskID: created.id,
                        stage: "curator_created",
                        channelID: nil,
                        workerID: nil,
                        message: "Self-improvement curator created patch plan.",
                        actorID: "system:self-improvement-curator"
                    )
                }
            } catch {
                patchPlanTaskID = nil
                logger.warning(
                    "self_improvement.curator.patch_plan_create_failed",
                    metadata: ["project_id": .string(normalizedProjectID), "error": .string(error.localizedDescription)]
                )
            }
        }

        return SelfImprovementCuratorProjectResult(
            projectID: normalizedProjectID,
            proposalCount: proposals.count,
            duplicateGroupCount: duplicateGroups.count,
            proposalTasksUpdated: proposalTasksUpdated,
            patchPlanTaskID: patchPlanTaskID,
            patchPlanCreated: patchPlanCreated,
            patchPlanUpdated: patchPlanUpdated
        )
    }

    private static let selfImprovementCuratorPatchPlanTags = [
        "self-improvement",
        "curator",
        "patch-plan",
    ]

    private static func selfImprovementCuratorPatchPlanTitle(project: ProjectRecord) -> String {
        "Self-improvement curator: \(project.name) patch plan"
    }

    private static func selfImprovementCuratorProposals(in project: ProjectRecord) -> [SelfImprovementCuratorProposal] {
        project.tasks
            .filter { task in
                !task.isArchived &&
                    activeSelfImprovementProposalStatuses.contains(task.status) &&
                    task.tags.contains("self-improvement") &&
                    task.tags.contains("proposal")
            }
            .map { task in
                let subsystem = markdownHeadingValue("Affected Subsystem", in: task.description)
                    ?? task.tags.first(where: { knownSelfImprovementSubsystemTags.contains($0) })
                    ?? "general"
                let classification = markdownHeadingValue("Failure Classification", in: task.description)
                return SelfImprovementCuratorProposal(
                    projectID: project.id,
                    projectName: project.name,
                    task: task,
                    groupKey: selfImprovementCuratorGroupKey(
                        task: task,
                        subsystem: subsystem,
                        classification: classification
                    ),
                    subsystem: subsystem,
                    classification: classification
                )
            }
            .sorted { $0.task.updatedAt > $1.task.updatedAt }
    }

    private static let activeSelfImprovementProposalStatuses: Set<String> = [
        ProjectTaskStatus.pendingApproval.rawValue,
        ProjectTaskStatus.backlog.rawValue,
        ProjectTaskStatus.ready.rawValue,
        ProjectTaskStatus.inProgress.rawValue,
        ProjectTaskStatus.waitingInput.rawValue,
        ProjectTaskStatus.needsReview.rawValue,
    ]

    private static let knownSelfImprovementSubsystemTags: Set<String> = [
        "skills",
        "runtime",
        "tools",
        "memory",
        "dashboard",
        "prompts",
        "mcp",
    ]

    private static func selfImprovementCuratorPatchPlanTask(in project: ProjectRecord) -> ProjectTask? {
        project.tasks
            .filter { task in
                !task.isArchived &&
                    activeSelfImprovementProposalStatuses.contains(task.status) &&
                    selfImprovementCuratorPatchPlanTags.allSatisfy { task.tags.contains($0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private static func selfImprovementCuratorGroupKey(
        task: ProjectTask,
        subsystem: String,
        classification: String?
    ) -> String {
        let normalizedSubsystem = normalizedCuratorKeyComponent(subsystem)
        let normalizedClassification = normalizedCuratorKeyComponent(classification ?? "general")
        let titleKey = normalizedCuratorTitleKey(task.title)
        return [normalizedSubsystem, normalizedClassification, titleKey].joined(separator: "::")
    }

    private static func normalizedCuratorTitleKey(_ title: String) -> String {
        var normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in [
            "self-improvement proposal:",
            "self improvement proposal:",
            "proposal:",
        ] where normalized.hasPrefix(prefix) {
            normalized = String(normalized.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let folded = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        let tokens = String(folded)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token != "duplicate" && token != "copy"
            }
        return tokens.prefix(4).joined(separator: "-")
    }

    private static func normalizedCuratorKeyComponent(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func descriptionByReplacingCuratorDuplicateSection(
        _ description: String,
        group: [SelfImprovementCuratorProposal],
        canonical: SelfImprovementCuratorProposal,
        reason: String
    ) -> String {
        let related = group
            .map { proposal in
                "- `\(proposal.task.id)` \(proposal.task.title)"
            }
            .joined(separator: "\n")
        let section = """
        ## Curator Duplicate Group
        Reason: \(reason)

        Canonical proposal: `\(canonical.task.id)` \(canonical.task.title)

        Related proposals:
        \(related)
        """
        return replacingMarkdownSection(
            "Curator Duplicate Group",
            in: description,
            with: section
        )
    }

    private static func selfImprovementCuratorPatchPlanDescription(
        project: ProjectRecord,
        proposals: [SelfImprovementCuratorProposal],
        groupedProposals: [String: [SelfImprovementCuratorProposal]],
        reason: String
    ) -> String {
        let duplicateGroups = groupedProposals.values
            .filter { $0.count > 1 }
            .map { sortedSelfImprovementCuratorGroup($0) }
            .sorted { ($0.first?.groupKey ?? "") < ($1.first?.groupKey ?? "") }

        let duplicateSection: String
        if duplicateGroups.isEmpty {
            duplicateSection = "No duplicate proposal groups were detected in this curator run."
        } else {
            duplicateSection = duplicateGroups.enumerated().map { index, group in
                let canonical = group[0]
                let duplicateIDs = group
                    .dropFirst()
                    .map { "`\($0.task.id)`" }
                    .joined(separator: ", ")
                let tasks = group.map { "- `\($0.task.id)` \($0.task.title)" }.joined(separator: "\n")
                let verification = selfImprovementCuratorVerificationCommands(from: group)
                let verificationSection = verification.isEmpty
                    ? "No required verification commands were found in the source proposals."
                    : verification.map { "- \($0)" }.joined(separator: "\n")
                return """
                ### Group \(index + 1): \(canonical.subsystem)
                Classification: \(canonical.classification ?? "general")
                Canonical proposal: `\(canonical.task.id)` \(canonical.task.title)
                Duplicate proposal ids: \(duplicateIDs.isEmpty ? "(none)" : duplicateIDs)
                Recommended implementation task title: \(selfImprovementCuratorImplementationTaskTitle(for: canonical))

                \(tasks)

                Required verification commands:
                \(verificationSection)
                """
            }.joined(separator: "\n\n")
        }

        let standalone = proposals
            .filter { proposal in
                (groupedProposals[proposal.groupKey]?.count ?? 0) == 1
            }
            .map { "- `\($0.task.id)` \($0.task.title) [\($0.subsystem)]" }
            .joined(separator: "\n")

        let patchSteps: String
        if proposals.isEmpty {
            patchSteps = "No open proposal tasks are available for patch planning."
        } else {
            patchSteps = """
            1. Review each duplicate group and choose the canonical proposal scope before implementation.
            2. Convert approved proposal groups into focused patch tasks; keep skill/core prompt changes in their own approval/apply flow.
            3. Preserve evidence links from source proposal tasks in the implementation handoff.
            4. Leave source proposal tasks open until the approved patch task exists, then update their status according to project policy.
            """
        }

        let standaloneSection = standalone.isEmpty
            ? "No standalone proposal tasks were found."
            : standalone

        return """
        ## Goal
        Curate open self-improvement proposal tasks for `\(project.name)` and produce an approval-ready patch plan.

        ## Context
        Curator run reason: \(reason)
        Open proposal tasks reviewed: \(proposals.count)

        ## Duplicate Groups
        \(duplicateSection)

        ## Standalone Proposals
        \(standaloneSection)

        ## Patch Plan
        \(patchSteps)

        ## Risk
        This task is a review and planning artifact only. It must not directly change skills, core prompts, runtime code, files, repositories, browser state, shell state, or MCP configuration.

        ## Definition of Done
        Duplicate proposal groups have a selected canonical scope, approved follow-up patch tasks exist where needed, and proposal tasks retain enough evidence for audit.

        ## Tests / Verification
        Verify any follow-up implementation with the narrow tests named in the approved proposal tasks, then run the relevant CI-parity command for the touched subsystem.
        """
    }

    private static func replacingMarkdownSection(
        _ heading: String,
        in description: String,
        with replacement: String
    ) -> String {
        let normalizedHeading = "## \(heading)"
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHeading.lowercased()
        }) else {
            let separator = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            return description.trimmingCharacters(in: .whitespacesAndNewlines) + separator + replacement
        }

        let end = lines.dropFirst(start + 1).firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
        }) ?? lines.endIndex
        var updated = lines
        updated.replaceSubrange(start..<end, with: replacement.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        return updated.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownHeadingValue(_ heading: String, in description: String) -> String? {
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let target = "## \(heading)".lowercased()
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }) else {
            return nil
        }

        for line in lines.dropFirst(headingIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                return nil
            }
            let value = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*: `"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value.lowercased()
            }
        }
        return nil
    }

    private static func sortedSelfImprovementCuratorGroup(
        _ group: [SelfImprovementCuratorProposal]
    ) -> [SelfImprovementCuratorProposal] {
        group.sorted { lhs, rhs in
            if lhs.task.createdAt == rhs.task.createdAt {
                return lhs.task.id < rhs.task.id
            }
            return lhs.task.createdAt < rhs.task.createdAt
        }
    }

    private static func selfImprovementCuratorImplementationTaskTitle(
        for proposal: SelfImprovementCuratorProposal
    ) -> String {
        var title = proposal.task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [
            "Self-improvement proposal:",
            "Self improvement proposal:",
            "Proposal:",
        ] where title.lowercased().hasPrefix(prefix.lowercased()) {
            title = String(title.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return "Implement self-improvement proposal: \(title)"
    }

    private static func selfImprovementCuratorVerificationCommands(
        from proposals: [SelfImprovementCuratorProposal]
    ) -> [String] {
        var seen: Set<String> = []
        var commands: [String] = []
        for proposal in proposals {
            guard let body = markdownHeadingBody("Tests / Verification", in: proposal.task.description) else {
                continue
            }
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let command = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*` "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty, !seen.contains(command) else { continue }
                seen.insert(command)
                commands.append(command)
            }
        }
        return commands
    }

    private static func markdownHeadingBody(_ heading: String, in description: String) -> String? {
        let lines = description.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let target = "## \(heading)".lowercased()
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }) else {
            return nil
        }
        let bodyLines = lines.dropFirst(headingIndex + 1).prefix { line in
            !line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ")
        }
        let body = bodyLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}
