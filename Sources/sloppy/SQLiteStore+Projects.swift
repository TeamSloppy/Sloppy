import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
#endif

extension SQLiteStore {
    public func listProjects() async -> [ProjectRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackProjects.values.sorted { $0.createdAt < $1.createdAt }
        }

        let sql =
            """
            SELECT id, name, description, actors_json, teams_json,
                   models_json, agent_files_json, heartbeat_json,
                   created_at, updated_at, repo_path, review_settings_json,
                   icon, is_archived, task_loop_mode, task_sync_settings_json,
                   is_favorite, source_control_provider_id, autopilot_settings_json,
                   project_kind, directory_paths_json, automatic_task_pickup_enabled
            FROM dashboard_projects
            ORDER BY created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackProjects.values.sorted { $0.createdAt < $1.createdAt }
        }
        defer { sqlite3_finalize(statement) }

        var result: [ProjectRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let namePtr = sqlite3_column_text(statement, 1),
                let descriptionPtr = sqlite3_column_text(statement, 2),
                let actorsPtr = sqlite3_column_text(statement, 3),
                let teamsPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 8),
                let updatedAtPtr = sqlite3_column_text(statement, 9)
            else {
                continue
            }

            let id = String(cString: idPtr)
            let name = String(cString: namePtr)
            let description = String(cString: descriptionPtr)
            let actorsJSON = String(cString: actorsPtr)
            let teamsJSON = String(cString: teamsPtr)
            let modelsJSON = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
            let agentFilesJSON = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "[]"
            let heartbeatJSON = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "{}"
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
            let actors = (try? JSONDecoder().decode([String].self, from: Data(actorsJSON.utf8))) ?? []
            let teams = (try? JSONDecoder().decode([String].self, from: Data(teamsJSON.utf8))) ?? []
            let models = (try? JSONDecoder().decode([String].self, from: Data(modelsJSON.utf8))) ?? []
            let agentFiles = (try? JSONDecoder().decode([String].self, from: Data(agentFilesJSON.utf8))) ?? []
            let heartbeat = (try? JSONDecoder().decode(ProjectHeartbeatSettings.self, from: Data(heartbeatJSON.utf8))) ?? ProjectHeartbeatSettings()
            let repoPath = optionalText(statement: statement, index: 10)
            let reviewSettingsJSON = sqlite3_column_text(statement, 11).map { String(cString: $0) }
            let reviewSettings = reviewSettingsJSON.flatMap { try? JSONDecoder().decode(ProjectReviewSettings.self, from: Data($0.utf8)) } ?? ProjectReviewSettings()
            let autopilotSettingsJSON = sqlite3_column_text(statement, 18).map { String(cString: $0) } ?? "{}"
            let autopilotSettings = (try? JSONDecoder().decode(ProjectAutopilotSettings.self, from: Data(autopilotSettingsJSON.utf8))) ?? ProjectAutopilotSettings()
            let icon = optionalText(statement: statement, index: 12)
            let isArchived = sqlite3_column_int(statement, 13) != 0
            let taskLoopModeRaw = optionalText(statement: statement, index: 14)
            let taskLoopMode = taskLoopModeRaw.flatMap { ProjectLoopMode(rawValue: $0) } ?? .human
            let taskSyncJSON = sqlite3_column_text(statement, 15).map { String(cString: $0) } ?? "{}"
            let taskSyncSettings = (try? JSONDecoder().decode(ProjectTaskSyncSettings.self, from: Data(taskSyncJSON.utf8))) ?? ProjectTaskSyncSettings()
            let isFavorite = sqlite3_column_int(statement, 16) != 0
            let sourceControlProviderId = optionalText(statement: statement, index: 17)
            let kind = optionalText(statement: statement, index: 19).flatMap(ProjectKind.init(rawValue:)) ?? .project
            let directoryPathsJSON = sqlite3_column_text(statement, 20).map { String(cString: $0) } ?? "[]"
            let directoryPaths = (try? JSONDecoder().decode([String].self, from: Data(directoryPathsJSON.utf8))) ?? []
            let channels = loadProjectChannels(db: db, projectID: id)
            let tasks = loadProjectTasks(db: db, projectID: id)
            if let fallback = fallbackProjects[id], fallback.tasks.count > tasks.count {
                result.append(fallback)
                continue
            }
            result.append(
                ProjectRecord(
                    id: id,
                    name: name,
                    description: description,
                    icon: icon,
                    kind: kind,
                    directoryPaths: directoryPaths,
                    channels: channels,
                    tasks: tasks,
                    actors: actors,
                    teams: teams,
                    models: models,
                    agentFiles: agentFiles,
                    heartbeat: heartbeat,
                    repoPath: repoPath,
                    sourceControlProviderId: sourceControlProviderId,
                    reviewSettings: reviewSettings,
                    automaticTaskPickupEnabled: sqlite3_column_int(statement, 21) != 0,
                    autopilotSettings: autopilotSettings,
                    taskLoopMode: taskLoopMode,
                    taskSyncSettings: taskSyncSettings,
                    isFavorite: isFavorite,
                    isArchived: isArchived,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
#else
        return fallbackProjects.values.sorted { $0.createdAt < $1.createdAt }
#endif
    }

    public func listProjectSummaries() async -> [ProjectListRecord] {
#if canImport(CSQLite3)
        guard let db else {
            return fallbackProjects.values.map(Self.projectListRecord).sorted { $0.createdAt < $1.createdAt }
        }

        let sql =
            """
            SELECT p.id, p.name, p.description, p.actors_json, p.teams_json,
                   p.created_at, p.updated_at, p.repo_path, p.icon, p.is_archived,
                   p.is_favorite, p.source_control_provider_id,
                   COUNT(t.id) AS task_total,
                   SUM(CASE WHEN t.status = 'backlog' THEN 1 ELSE 0 END) AS task_backlog,
                   SUM(CASE WHEN t.status = 'ready' THEN 1 ELSE 0 END) AS task_ready,
                   SUM(CASE WHEN t.status = 'in_progress' THEN 1 ELSE 0 END) AS task_in_progress,
                   SUM(CASE WHEN t.status = 'waiting_input' THEN 1 ELSE 0 END) AS task_waiting_input,
                   SUM(CASE WHEN t.status = 'blocked' THEN 1 ELSE 0 END) AS task_blocked,
                   SUM(CASE WHEN t.status = 'needs_review' THEN 1 ELSE 0 END) AS task_needs_review,
                   SUM(CASE WHEN t.status = 'done' THEN 1 ELSE 0 END) AS task_done,
                   p.project_kind, p.directory_paths_json
            FROM dashboard_projects p
            LEFT JOIN dashboard_project_tasks t ON t.project_id = p.id
            GROUP BY p.id
            ORDER BY p.created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return fallbackProjects.values.map(Self.projectListRecord).sorted { $0.createdAt < $1.createdAt }
        }
        defer { sqlite3_finalize(statement) }

        var result: [ProjectListRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let namePtr = sqlite3_column_text(statement, 1),
                let descriptionPtr = sqlite3_column_text(statement, 2),
                let actorsPtr = sqlite3_column_text(statement, 3),
                let teamsPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 5),
                let updatedAtPtr = sqlite3_column_text(statement, 6)
            else {
                continue
            }

            let id = String(cString: idPtr)
            let actorsJSON = String(cString: actorsPtr)
            let teamsJSON = String(cString: teamsPtr)
            let actors = (try? JSONDecoder().decode([String].self, from: Data(actorsJSON.utf8))) ?? []
            let teams = (try? JSONDecoder().decode([String].self, from: Data(teamsJSON.utf8))) ?? []
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
            let taskTotal = Int(sqlite3_column_int(statement, 12))
            if let fallback = fallbackProjects[id], fallback.tasks.count > taskTotal {
                result.append(Self.projectListRecord(fallback))
                continue
            }
            result.append(
                ProjectListRecord(
                    id: id,
                    name: String(cString: namePtr),
                    description: String(cString: descriptionPtr),
                    icon: optionalText(statement: statement, index: 8),
                    kind: optionalText(statement: statement, index: 20).flatMap(ProjectKind.init(rawValue:)) ?? .project,
                    directoryPaths: sqlite3_column_text(statement, 21).flatMap {
                        try? JSONDecoder().decode([String].self, from: Data(String(cString: $0).utf8))
                    } ?? [],
                    channels: loadProjectChannels(db: db, projectID: id),
                    actors: actors,
                    teams: teams,
                    repoPath: optionalText(statement: statement, index: 7),
                    sourceControlProviderId: optionalText(statement: statement, index: 11),
                    taskCounts: ProjectTaskCountSummary(
                        total: taskTotal,
                        backlog: Int(sqlite3_column_int(statement, 13)),
                        ready: Int(sqlite3_column_int(statement, 14)),
                        inProgress: Int(sqlite3_column_int(statement, 15)),
                        waitingInput: Int(sqlite3_column_int(statement, 16)),
                        blocked: Int(sqlite3_column_int(statement, 17)),
                        needsReview: Int(sqlite3_column_int(statement, 18)),
                        done: Int(sqlite3_column_int(statement, 19))
                    ),
                    isFavorite: sqlite3_column_int(statement, 10) != 0,
                    isArchived: sqlite3_column_int(statement, 9) != 0,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }

        return result
#else
        return fallbackProjects.values.map(Self.projectListRecord).sorted { $0.createdAt < $1.createdAt }
#endif
    }

    public func project(id: String) async -> ProjectRecord? {
#if canImport(CSQLite3)
        if let db {
            let sql =
                """
                SELECT id, name, description, actors_json, teams_json,
                       models_json, agent_files_json, heartbeat_json,
                       created_at, updated_at, repo_path, review_settings_json,
                       icon, is_archived, task_loop_mode, task_sync_settings_json,
                       is_favorite, source_control_provider_id, autopilot_settings_json,
                       project_kind, directory_paths_json, automatic_task_pickup_enabled
                FROM dashboard_projects
                WHERE id = ?
                LIMIT 1;
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return fallbackProjects[id]
            }
            defer { sqlite3_finalize(statement) }

            bindText(id, at: 1, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW,
               let idPtr = sqlite3_column_text(statement, 0),
               let namePtr = sqlite3_column_text(statement, 1),
               let descriptionPtr = sqlite3_column_text(statement, 2),
               let actorsPtr = sqlite3_column_text(statement, 3),
               let teamsPtr = sqlite3_column_text(statement, 4),
               let createdAtPtr = sqlite3_column_text(statement, 8),
               let updatedAtPtr = sqlite3_column_text(statement, 9) {
                let projectID = String(cString: idPtr)
                let actorsJSON = String(cString: actorsPtr)
                let teamsJSON = String(cString: teamsPtr)
                let modelsJSON = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
                let agentFilesJSON = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "[]"
                let heartbeatJSON = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? "{}"
                let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
                let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
                let actors = (try? JSONDecoder().decode([String].self, from: Data(actorsJSON.utf8))) ?? []
                let teams = (try? JSONDecoder().decode([String].self, from: Data(teamsJSON.utf8))) ?? []
                let models = (try? JSONDecoder().decode([String].self, from: Data(modelsJSON.utf8))) ?? []
                let agentFiles = (try? JSONDecoder().decode([String].self, from: Data(agentFilesJSON.utf8))) ?? []
                let heartbeat = (try? JSONDecoder().decode(ProjectHeartbeatSettings.self, from: Data(heartbeatJSON.utf8))) ?? ProjectHeartbeatSettings()
                let repoPath = optionalText(statement: statement, index: 10)
                let reviewSettingsJSON = sqlite3_column_text(statement, 11).map { String(cString: $0) }
                let reviewSettings = reviewSettingsJSON.flatMap { try? JSONDecoder().decode(ProjectReviewSettings.self, from: Data($0.utf8)) } ?? ProjectReviewSettings()
                let autopilotSettingsJSON = sqlite3_column_text(statement, 18).map { String(cString: $0) } ?? "{}"
                let autopilotSettings = (try? JSONDecoder().decode(ProjectAutopilotSettings.self, from: Data(autopilotSettingsJSON.utf8))) ?? ProjectAutopilotSettings()
                let icon = optionalText(statement: statement, index: 12)
                let isArchived = sqlite3_column_int(statement, 13) != 0
                let taskLoopModeRaw = optionalText(statement: statement, index: 14)
                let taskLoopMode = taskLoopModeRaw.flatMap { ProjectLoopMode(rawValue: $0) } ?? .human
                let taskSyncJSON = sqlite3_column_text(statement, 15).map { String(cString: $0) } ?? "{}"
                let taskSyncSettings = (try? JSONDecoder().decode(ProjectTaskSyncSettings.self, from: Data(taskSyncJSON.utf8))) ?? ProjectTaskSyncSettings()
                let isFavorite = sqlite3_column_int(statement, 16) != 0
                let sourceControlProviderId = optionalText(statement: statement, index: 17)
                let kind = optionalText(statement: statement, index: 19).flatMap(ProjectKind.init(rawValue:)) ?? .project
                let directoryPathsJSON = sqlite3_column_text(statement, 20).map { String(cString: $0) } ?? "[]"
                let directoryPaths = (try? JSONDecoder().decode([String].self, from: Data(directoryPathsJSON.utf8))) ?? []
                let tasks = loadProjectTasks(db: db, projectID: projectID)
                if let fallback = fallbackProjects[id], fallback.tasks.count > tasks.count {
                    return fallback
                }
                return ProjectRecord(
                    id: projectID,
                    name: String(cString: namePtr),
                    description: String(cString: descriptionPtr),
                    icon: icon,
                    kind: kind,
                    directoryPaths: directoryPaths,
                    channels: loadProjectChannels(db: db, projectID: projectID),
                    tasks: tasks,
                    actors: actors,
                    teams: teams,
                    models: models,
                    agentFiles: agentFiles,
                    heartbeat: heartbeat,
                    repoPath: repoPath,
                    sourceControlProviderId: sourceControlProviderId,
                    reviewSettings: reviewSettings,
                    automaticTaskPickupEnabled: sqlite3_column_int(statement, 21) != 0,
                    autopilotSettings: autopilotSettings,
                    taskLoopMode: taskLoopMode,
                    taskSyncSettings: taskSyncSettings,
                    isFavorite: isFavorite,
                    isArchived: isArchived,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
            return nil
        }
#endif
        return fallbackProjects[id]
    }

    public func saveProject(_ project: ProjectRecord) async {
        fallbackProjects[project.id] = project
        persistFallbackProjectsToDisk()
#if canImport(CSQLite3)
        guard let db else {
            return
        }

        let projectSQL =
            """
            INSERT OR REPLACE INTO dashboard_projects(
                id,
                name,
                description,
                actors_json,
                teams_json,
                models_json,
                agent_files_json,
                heartbeat_json,
                created_at,
                updated_at,
                repo_path,
                review_settings_json,
                autopilot_settings_json,
                icon,
                is_archived,
                task_loop_mode,
                task_sync_settings_json,
                is_favorite,
                source_control_provider_id,
                project_kind,
                directory_paths_json,
                automatic_task_pickup_enabled
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var projectStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, projectSQL, -1, &projectStatement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(projectStatement) }

        let actorsJSON = (try? String(data: JSONEncoder().encode(project.actors), encoding: .utf8)) ?? "[]"
        let teamsJSON = (try? String(data: JSONEncoder().encode(project.teams), encoding: .utf8)) ?? "[]"
        let modelsJSON = (try? String(data: JSONEncoder().encode(project.models), encoding: .utf8)) ?? "[]"
        let agentFilesJSON = (try? String(data: JSONEncoder().encode(project.agentFiles), encoding: .utf8)) ?? "[]"
        let heartbeatJSON = (try? String(data: JSONEncoder().encode(project.heartbeat), encoding: .utf8)) ?? "{}"
        let reviewSettingsJSON = (try? String(data: JSONEncoder().encode(project.reviewSettings), encoding: .utf8)) ?? "{}"
        let autopilotSettingsJSON = (try? String(data: JSONEncoder().encode(project.autopilotSettings), encoding: .utf8)) ?? "{}"
        let taskSyncSettingsJSON = (try? String(data: JSONEncoder().encode(project.taskSyncSettings), encoding: .utf8)) ?? "{}"
        let directoryPathsJSON = (try? String(data: JSONEncoder().encode(project.directoryPaths), encoding: .utf8)) ?? "[]"

        bindText(project.id, at: 1, statement: projectStatement)
        bindText(project.name, at: 2, statement: projectStatement)
        bindText(project.description, at: 3, statement: projectStatement)
        bindText(actorsJSON, at: 4, statement: projectStatement)
        bindText(teamsJSON, at: 5, statement: projectStatement)
        bindText(modelsJSON, at: 6, statement: projectStatement)
        bindText(agentFilesJSON, at: 7, statement: projectStatement)
        bindText(heartbeatJSON, at: 8, statement: projectStatement)
        bindText(isoFormatter.string(from: project.createdAt), at: 9, statement: projectStatement)
        bindText(isoFormatter.string(from: project.updatedAt), at: 10, statement: projectStatement)
        bindOptionalText(project.repoPath, at: 11, statement: projectStatement)
        bindText(reviewSettingsJSON, at: 12, statement: projectStatement)
        bindText(autopilotSettingsJSON, at: 13, statement: projectStatement)
        bindOptionalText(project.icon, at: 14, statement: projectStatement)
        sqlite3_bind_int(projectStatement, 15, project.isArchived ? 1 : 0)
        bindText(project.taskLoopMode.rawValue, at: 16, statement: projectStatement)
        bindText(taskSyncSettingsJSON, at: 17, statement: projectStatement)
        sqlite3_bind_int(projectStatement, 18, project.isFavorite ? 1 : 0)
        bindOptionalText(project.sourceControlProviderId, at: 19, statement: projectStatement)
        bindText(project.kind.rawValue, at: 20, statement: projectStatement)
        bindText(directoryPathsJSON, at: 21, statement: projectStatement)
        sqlite3_bind_int(projectStatement, 22, project.automaticTaskPickupEnabled ? 1 : 0)
        guard sqlite3_step(projectStatement) == SQLITE_DONE else {
            return
        }

        removeProjectChildren(db: db, projectID: project.id)

        let channelSQL =
            """
            INSERT INTO dashboard_project_channels(
                id,
                project_id,
                title,
                channel_id,
                created_at
            ) VALUES(?, ?, ?, ?, ?);
            """

        for channel in project.channels {
            var channelStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, channelSQL, -1, &channelStatement, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_finalize(channelStatement) }
            bindText(channel.id, at: 1, statement: channelStatement)
            bindText(project.id, at: 2, statement: channelStatement)
            bindText(channel.title, at: 3, statement: channelStatement)
            bindText(channel.channelId, at: 4, statement: channelStatement)
            bindText(isoFormatter.string(from: channel.createdAt), at: 5, statement: channelStatement)
            _ = sqlite3_step(channelStatement)
        }

        let taskSQL =
            """
            INSERT INTO dashboard_project_tasks(
                id,
                project_id,
                title,
                description,
                priority,
                status,
                initiative_id,
                actor_id,
                team_id,
                claimed_actor_id,
                claimed_agent_id,
                parent_task_id,
                created_by,
                depends_on_task_ids_json,
                swarm_id,
                swarm_task_id,
                swarm_parent_task_id,
                swarm_dependency_ids_json,
                swarm_depth,
                swarm_actor_path_json,
                created_at,
                updated_at,
                worktree_branch,
                source_control_provider_id,
                kind,
                loop_mode_override,
                origin_type,
                origin_channel_id,
                is_archived,
                selected_model,
                attachments_json,
                external_metadata_json,
                tags_json,
                execution_node_id,
                kanban_column_entered_at,
                stage_assignments_json,
                active_stage
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        for task in project.tasks {
            var taskStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, taskSQL, -1, &taskStatement, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_finalize(taskStatement) }
            let dependencyIdsJSON = encodedStringArray(task.swarmDependencyIds ?? [])
            let dependsOnTaskIdsJSON = encodedStringArray(task.dependsOnTaskIds)
            let actorPathJSON = encodedStringArray(task.swarmActorPath ?? [])
            let attachmentsJSON = (try? String(data: JSONEncoder().encode(task.attachments), encoding: .utf8)) ?? "[]"
            let externalJSON = task.externalMetadata.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
            let tagsJSON = encodedStringArray(task.tags)
            bindText(task.id, at: 1, statement: taskStatement)
            bindText(project.id, at: 2, statement: taskStatement)
            bindText(task.title, at: 3, statement: taskStatement)
            bindText(task.description, at: 4, statement: taskStatement)
            bindText(task.priority, at: 5, statement: taskStatement)
            bindText(task.status, at: 6, statement: taskStatement)
            bindOptionalText(task.initiativeID, at: 7, statement: taskStatement)
            bindOptionalText(task.actorId, at: 8, statement: taskStatement)
            bindOptionalText(task.teamId, at: 9, statement: taskStatement)
            bindOptionalText(task.claimedActorId, at: 10, statement: taskStatement)
            bindOptionalText(task.claimedAgentId, at: 11, statement: taskStatement)
            bindOptionalText(task.parentTaskId, at: 12, statement: taskStatement)
            bindOptionalText(task.createdBy, at: 13, statement: taskStatement)
            bindText(dependsOnTaskIdsJSON, at: 14, statement: taskStatement)
            bindOptionalText(task.swarmId, at: 15, statement: taskStatement)
            bindOptionalText(task.swarmTaskId, at: 16, statement: taskStatement)
            bindOptionalText(task.swarmParentTaskId, at: 17, statement: taskStatement)
            bindText(dependencyIdsJSON, at: 18, statement: taskStatement)
            if let swarmDepth = task.swarmDepth {
                sqlite3_bind_int(taskStatement, 19, Int32(swarmDepth))
            } else {
                sqlite3_bind_null(taskStatement, 19)
            }
            bindText(actorPathJSON, at: 20, statement: taskStatement)
            bindText(isoFormatter.string(from: task.createdAt), at: 21, statement: taskStatement)
            bindText(isoFormatter.string(from: task.updatedAt), at: 22, statement: taskStatement)
            bindOptionalText(task.worktreeBranch, at: 23, statement: taskStatement)
            bindOptionalText(task.sourceControlProviderId, at: 24, statement: taskStatement)
            bindOptionalText(task.kind?.rawValue, at: 25, statement: taskStatement)
            bindOptionalText(task.loopModeOverride?.rawValue, at: 26, statement: taskStatement)
            bindOptionalText(task.originType?.rawValue, at: 27, statement: taskStatement)
            bindOptionalText(task.originChannelId, at: 28, statement: taskStatement)
            sqlite3_bind_int(taskStatement, 29, task.isArchived ? 1 : 0)
            bindOptionalText(task.selectedModel, at: 30, statement: taskStatement)
            bindText(attachmentsJSON, at: 31, statement: taskStatement)
            bindOptionalText(externalJSON, at: 32, statement: taskStatement)
            bindText(tagsJSON, at: 33, statement: taskStatement)
            bindOptionalText(task.executionNodeId, at: 34, statement: taskStatement)
            bindOptionalText(task.kanbanColumnEnteredAt.map { isoFormatter.string(from: $0) }, at: 35, statement: taskStatement)
            let assignmentsJSON = task.stageAssignments.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
            bindOptionalText(assignmentsJSON, at: 36, statement: taskStatement)
            bindOptionalText(task.activeStage?.rawValue, at: 37, statement: taskStatement)
            _ = sqlite3_step(taskStatement)
        }
#endif
    }

    public func deleteProject(id: String) async {
        fallbackProjects[id] = nil
        persistFallbackProjectsToDisk()
#if canImport(CSQLite3)
        guard let db else {
            return
        }

        removeProjectChildren(db: db, projectID: id)

        let sql =
            """
            DELETE FROM dashboard_projects
            WHERE id = ?;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindText(id, at: 1, statement: statement)
        _ = sqlite3_step(statement)
#endif
    }

    func persistFallbackProjectsToDisk() {
        let projects = fallbackProjects.values.sorted { left, right in
            left.createdAt < right.createdAt
        }

        let parentDirectory = fallbackProjectsFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let payload = try? encoder.encode(projects) else {
            return
        }

        try? payload.write(to: fallbackProjectsFileURL, options: .atomic)
    }

    static func projectListRecord(_ project: ProjectRecord) -> ProjectListRecord {
        var counts = ProjectTaskCountSummary(total: project.tasks.count)
        for task in project.tasks {
            switch ProjectTaskStatus(rawValue: task.status) {
            case .backlog: counts.backlog += 1
            case .ready: counts.ready += 1
            case .inProgress: counts.inProgress += 1
            case .waitingInput: counts.waitingInput += 1
            case .blocked: counts.blocked += 1
            case .needsReview: counts.needsReview += 1
            case .done: counts.done += 1
            default: break
            }
        }
        return ProjectListRecord(
            id: project.id,
            name: project.name,
            description: project.description,
            icon: project.icon,
            kind: project.kind,
            directoryPaths: project.directoryPaths,
            channels: project.channels,
            actors: project.actors,
            teams: project.teams,
            repoPath: project.repoPath,
            sourceControlProviderId: project.sourceControlProviderId,
            taskCounts: counts,
            isFavorite: project.isFavorite,
            isArchived: project.isArchived,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
    }

#if canImport(CSQLite3)
    func removeProjectChildren(db: OpaquePointer, projectID: String) {
        let deleteChannelsSQL =
            """
            DELETE FROM dashboard_project_channels
            WHERE project_id = ?;
            """
        var channelsStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteChannelsSQL, -1, &channelsStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(channelsStatement) }
            bindText(projectID, at: 1, statement: channelsStatement)
            _ = sqlite3_step(channelsStatement)
        }

        let deleteTasksSQL =
            """
            DELETE FROM dashboard_project_tasks
            WHERE project_id = ?;
            """
        var tasksStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteTasksSQL, -1, &tasksStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(tasksStatement) }
            bindText(projectID, at: 1, statement: tasksStatement)
            _ = sqlite3_step(tasksStatement)
        }
    }
#endif

#if canImport(CSQLite3)
    func loadProjectChannels(db: OpaquePointer, projectID: String) -> [ProjectChannel] {
        let sql =
            """
            SELECT id, title, channel_id, created_at
            FROM dashboard_project_channels
            WHERE project_id = ?
            ORDER BY created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bindText(projectID, at: 1, statement: statement)

        var result: [ProjectChannel] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let titlePtr = sqlite3_column_text(statement, 1),
                let channelIDPtr = sqlite3_column_text(statement, 2),
                let createdAtPtr = sqlite3_column_text(statement, 3)
            else {
                continue
            }
            result.append(
                ProjectChannel(
                    id: String(cString: idPtr),
                    title: String(cString: titlePtr),
                    channelId: String(cString: channelIDPtr),
                    createdAt: isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
                )
            )
        }

        return result
    }
#endif

#if canImport(CSQLite3)
    func loadProjectTasks(db: OpaquePointer, projectID: String) -> [ProjectTask] {
        let sql =
            """
            SELECT
                id,
                title,
                description,
                priority,
                status,
                initiative_id,
                actor_id,
                team_id,
                claimed_actor_id,
                claimed_agent_id,
                parent_task_id,
                created_by,
                depends_on_task_ids_json,
                swarm_id,
                swarm_task_id,
                swarm_parent_task_id,
                swarm_dependency_ids_json,
                swarm_depth,
                swarm_actor_path_json,
                created_at,
                updated_at,
                worktree_branch,
                source_control_provider_id,
                kind,
                loop_mode_override,
                origin_type,
                origin_channel_id,
                is_archived,
                selected_model,
                attachments_json,
                external_metadata_json,
                tags_json,
                execution_node_id,
                kanban_column_entered_at,
                stage_assignments_json,
                active_stage
            FROM dashboard_project_tasks
            WHERE project_id = ?
            ORDER BY created_at ASC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bindText(projectID, at: 1, statement: statement)

        var result: [ProjectTask] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idPtr = sqlite3_column_text(statement, 0),
                let titlePtr = sqlite3_column_text(statement, 1),
                let descriptionPtr = sqlite3_column_text(statement, 2),
                let priorityPtr = sqlite3_column_text(statement, 3),
                let statusPtr = sqlite3_column_text(statement, 4),
                let createdAtPtr = sqlite3_column_text(statement, 19),
                let updatedAtPtr = sqlite3_column_text(statement, 20)
            else {
                continue
            }
            let createdAt = isoFormatter.date(from: String(cString: createdAtPtr)) ?? Date()
            let updatedAt = isoFormatter.date(from: String(cString: updatedAtPtr)) ?? createdAt
            let dependsOnTaskIds = decodeOptionalStringArray(optionalText(statement: statement, index: 12)) ?? []
            let dependencyIds = decodeOptionalStringArray(optionalText(statement: statement, index: 16))
            let actorPath = decodeOptionalStringArray(optionalText(statement: statement, index: 18))
            let kindRaw = optionalText(statement: statement, index: 23)
            let loopOverrideRaw = optionalText(statement: statement, index: 24)
            let originTypeRaw = optionalText(statement: statement, index: 25)
            let attachmentsJSON = optionalText(statement: statement, index: 29)
            let attachments = attachmentsJSON.flatMap { try? JSONDecoder().decode([AgentAttachmentUpload].self, from: Data($0.utf8)) } ?? []
            let externalJSON = optionalText(statement: statement, index: 30)
            let externalMetadata = externalJSON.flatMap { try? JSONDecoder().decode(TaskExternalMetadata.self, from: Data($0.utf8)) }
            let tags = decodeOptionalStringArray(optionalText(statement: statement, index: 31)) ?? []
            result.append(
                ProjectTask(
                    id: String(cString: idPtr),
                    title: String(cString: titlePtr),
                    description: String(cString: descriptionPtr),
                    priority: String(cString: priorityPtr),
                    status: String(cString: statusPtr),
                    initiativeID: optionalText(statement: statement, index: 5),
                    kind: kindRaw.flatMap { ProjectTaskKind(rawValue: $0) },
                    loopModeOverride: loopOverrideRaw.flatMap { ProjectLoopMode(rawValue: $0) },
                    originType: originTypeRaw.flatMap { TaskOriginType(rawValue: $0) },
                    originChannelId: optionalText(statement: statement, index: 26),
                    actorId: optionalText(statement: statement, index: 6),
                    executionNodeId: optionalText(statement: statement, index: 32),
                    teamId: optionalText(statement: statement, index: 7),
                    stageAssignments: optionalText(statement: statement, index: 34).flatMap {
                        try? JSONDecoder().decode(TaskStageAssignments.self, from: Data($0.utf8))
                    },
                    activeStage: optionalText(statement: statement, index: 35).flatMap(TaskExecutionStage.init(rawValue:)),
                    claimedActorId: optionalText(statement: statement, index: 8),
                    claimedAgentId: optionalText(statement: statement, index: 9),
                    parentTaskId: optionalText(statement: statement, index: 10),
                    createdBy: optionalText(statement: statement, index: 11),
                    dependsOnTaskIds: dependsOnTaskIds,
                    swarmId: optionalText(statement: statement, index: 13),
                    swarmTaskId: optionalText(statement: statement, index: 14),
                    swarmParentTaskId: optionalText(statement: statement, index: 15),
                    swarmDependencyIds: dependencyIds,
                    swarmDepth: optionalInt(statement: statement, index: 17),
                    swarmActorPath: actorPath,
                    worktreeBranch: optionalText(statement: statement, index: 21),
                    sourceControlProviderId: optionalText(statement: statement, index: 22),
                    selectedModel: optionalText(statement: statement, index: 28),
                    externalMetadata: externalMetadata,
                    attachments: attachments,
                    tags: tags,
                    isArchived: sqlite3_column_int(statement, 27) != 0,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    kanbanColumnEnteredAt: optionalText(statement: statement, index: 33).flatMap { isoFormatter.date(from: $0) }
                )
            )
        }

        return result
    }
#endif
}
