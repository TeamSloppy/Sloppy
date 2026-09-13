import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite
struct TeamAssignmentsTests {
    @Test
    func rolesAreScopedAndLegacyTeamsDecode() throws {
        let actor = ActorNode(id: "a", displayName: "Agent", kind: .agent, systemRole: .developer)
        let legacy = try JSONDecoder().decode(ActorTeam.self, from: Data(#"{"id":"team","name":"Team","memberActorIds":["a"]}"#.utf8))
        #expect(legacy.roles(for: actor) == [.developer])
        let reviewTeam = ActorTeam(id: "review", name: "Review", memberActorIds: ["a"], memberRoles: ["a": [.reviewer, .qa]])
        #expect(reviewTeam.roles(for: actor) == [.reviewer, .qa])
        #expect(reviewTeam.defaultAssignments(nodes: [actor]) == TaskStageAssignments(reviewer: "a", qa: "a"))
        #expect(legacy.roles(for: actor) == [.developer])
        let noRole = ActorTeam(id: "none", name: "None", memberActorIds: ["a"], memberRoles: ["a": []])
        #expect(noRole.roles(for: actor).isEmpty)
    }

    @Test
    func boardRoundTripPreservesMultipleRolesAndRemovesOrphans() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ActorBoardFileStore(workspaceRootURL: root)
        let node = ActorNode(id: "human:tester", displayName: "Tester", kind: .human)
        let team = ActorTeam(id: "team", name: "Team", memberActorIds: [node.id], memberRoles: [node.id: [.qa, .reviewer, .qa], "missing": [.developer]])
        _ = try store.saveBoard(.init(nodes: [node], links: [], teams: [team]), agents: [])
        let loaded = try ActorBoardFileStore(workspaceRootURL: root).loadBoard(agents: [])
        #expect(loaded.teams.first?.memberRoles == [node.id: [.qa, .reviewer]])
    }

    @Test
    func taskDefaultsSnapshotAndExplicitClear() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let actor = ActorNode(id: "human:tester", displayName: "Tester", kind: .human)
        _ = try await service.createActorNode(node: actor)
        let team = ActorTeam(id: "team", name: "Team", memberActorIds: [actor.id], memberRoles: [actor.id: [.developer, .reviewer, .qa]])
        _ = try await service.createActorTeam(team: team)
        let createdProject = try await service.createProject(.init(id: "roles", name: "Roles", description: "", channels: [], teams: [team.id]))
        let project = createdProject.project
        let created = try await service.createProjectTask(projectID: project.id, request: .init(title: "Assigned task"))
        let task = try #require(created.tasks.first)
        #expect(task.teamId == team.id)
        #expect(task.stageAssignments == TaskStageAssignments(developer: actor.id, reviewer: actor.id, qa: actor.id))
        var changed = team
        changed.memberRoles = [actor.id: []]
        _ = try await service.updateActorTeam(teamID: team.id, team: changed)
        let renamed = try await service.updateProjectTask(projectID: project.id, taskID: task.id, request: .init(title: "Renamed"))
        #expect(renamed.tasks.first?.stageAssignments == task.stageAssignments)
        let cleared = try await service.updateProjectTask(projectID: project.id, taskID: task.id, request: .init(stageAssignments: .init()))
        #expect(cleared.tasks.first?.stageAssignments == TaskStageAssignments())
        await #expect(throws: CoreService.ProjectError.invalidPayload) {
            try await service.updateProjectTask(projectID: project.id, taskID: task.id, request: .init(stageAssignments: .init(qa: "missing")))
        }
        var review = task
        review.claimedActorId = actor.id
        review.activeStage = .development
        let handoff = await service.nextTeamHandoffDelegate(project: project, task: review)
        #expect(handoff?.actorID == actor.id)
        review.activeStage = .review
        #expect(await service.nextTeamHandoffDelegate(project: project, task: review) == nil)
        let board = try await service.getActorBoard()
        #expect(await service.preferredActorIDs(for: review, board: board) == [actor.id])
        var unassigned = task
        unassigned.stageAssignments = .init()
        #expect(await service.resolveTaskDelegation(project: project, task: unassigned) == nil)
        let direct = try await service.createProjectTask(projectID: project.id, request: .init(title: "Direct assignment", actorId: actor.id))
        #expect(direct.tasks.last?.teamId == nil)
        _ = try await service.updateActorTeam(teamID: team.id, team: team)
        let directTask = try #require(direct.tasks.last)
        let moved = try await service.updateProjectTask(projectID: project.id, taskID: directTask.id,
            request: .init(actorId: "", teamId: team.id))
        #expect(moved.tasks.last?.stageAssignments?.developer == actor.id)


    }

    @Test
    func assignmentsSurviveSQLiteMigrationAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schemaURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/sloppy/Storage/schema.sql")
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)
        let oldSchema = schema.replacingOccurrences(of: "    stage_assignments_json TEXT,\n", with: "").replacingOccurrences(of: "    active_stage TEXT,\n", with: "")
        let path = root.appendingPathComponent("test.sqlite").path
        #expect(SQLiteStore.prepareDatabase(path: path, schemaSQL: oldSchema) == nil)
        let task = ProjectTask(id: "task", title: "Test", description: "", priority: "low", status: "needs_review", stageAssignments: .init(developer: "a", reviewer: "a", qa: "b"), activeStage: .review)
        let store = SQLiteStore(path: path, schemaSQL: schema)
        await store.saveProject(.init(id: "project", name: "Project", description: "", channels: [], tasks: [task]))
        let reopened = SQLiteStore(path: path, schemaSQL: schema, fallbackProjectsPath: root.appendingPathComponent("empty.json").path)
        let loaded = try #require(await reopened.project(id: "project")?.tasks.first)
        #expect(loaded.stageAssignments == task.stageAssignments)
        #expect(loaded.activeStage == .review)
    }
}
