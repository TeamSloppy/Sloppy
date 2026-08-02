import Foundation
import Testing
@testable import Protocols
@testable import sloppy

private func makeElement(
    id: String,
    text: String,
    revision: Int = 0,
    x: Double = 0
) -> WorkspaceElement {
    WorkspaceElement(
        id: id,
        kind: .sticky,
        bounds: WorkspaceRect(x: x, y: 0, width: 220, height: 160),
        data: ["text": .string(text)],
        revision: revision
    )
}

@Test
func canvasWorkspaceTransactionIsAttributedIdempotentAndPersisted() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let workspace = try await service.createCanvasWorkspace(
        request: WorkspaceCreateRequest(title: "Research"),
        ownerKind: .agent,
        ownerId: "agent-researcher"
    )
    let actor = WorkspaceActor(kind: .agent, id: "agent-researcher", displayName: "Researcher")
    let request = WorkspaceTransactionRequest(
        id: "tx-create-sticky",
        baseRevision: 0,
        operations: [
            WorkspaceOperation(
                kind: .createElement,
                element: makeElement(id: "sticky-1", text: "Hypothesis")
            ),
        ],
        summary: "Added hypothesis"
    )

    let first = try await service.commitCanvasWorkspaceTransaction(
        workspaceId: workspace.id,
        request: request,
        actor: actor
    )
    let duplicate = try await service.commitCanvasWorkspaceTransaction(
        workspaceId: workspace.id,
        request: request,
        actor: actor
    )
    let document = try await service.canvasWorkspaceDocument(
        id: workspace.id,
        principalKind: .agent,
        principalId: actor.id,
        isAdmin: false
    )

    #expect(first.id == duplicate.id)
    #expect(first.revision == 1)
    #expect(first.actor == actor)
    #expect(first.operations.first?.element?.revision == 1)
    #expect(document.revision == 1)
    #expect(document.elements.count == 1)
    #expect(document.elements.first?.revision == 1)
}

@Test
func canvasWorkspaceRejectsStaleSameElementEditWithoutPartialMutation() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let workspace = try await service.createCanvasWorkspace(
        request: WorkspaceCreateRequest(title: "Conflict test"),
        ownerKind: .agent,
        ownerId: "agent-1"
    )
    let actor = WorkspaceActor(kind: .agent, id: "agent-1")
    _ = try await service.commitCanvasWorkspaceTransaction(
        workspaceId: workspace.id,
        request: WorkspaceTransactionRequest(
            id: "tx-create",
            baseRevision: 0,
            operations: [
                WorkspaceOperation(kind: .createElement, element: makeElement(id: "sticky-1", text: "Original")),
            ]
        ),
        actor: actor
    )
    _ = try await service.commitCanvasWorkspaceTransaction(
        workspaceId: workspace.id,
        request: WorkspaceTransactionRequest(
            id: "tx-human-move",
            baseRevision: 1,
            expectedElementRevisions: ["sticky-1": 1],
            operations: [
                WorkspaceOperation(
                    kind: .updateElement,
                    element: makeElement(id: "sticky-1", text: "Moved", revision: 1, x: 80)
                ),
            ]
        ),
        actor: actor
    )

    do {
        _ = try await service.commitCanvasWorkspaceTransaction(
            workspaceId: workspace.id,
            request: WorkspaceTransactionRequest(
                id: "tx-stale-agent",
                baseRevision: 1,
                expectedElementRevisions: ["sticky-1": 1],
                operations: [
                    WorkspaceOperation(
                        kind: .updateElement,
                        element: makeElement(id: "sticky-1", text: "Stale overwrite", revision: 1)
                    ),
                    WorkspaceOperation(
                        kind: .createElement,
                        element: makeElement(id: "sticky-should-not-exist", text: "Partial")
                    ),
                ]
            ),
            actor: actor
        )
        Issue.record("Expected a workspace conflict")
    } catch let error as CoreService.WorkspaceError {
        guard case .conflict(let latestRevision, let ids) = error else {
            Issue.record("Unexpected workspace error: \(error)")
            return
        }
        #expect(latestRevision == 2)
        #expect(ids == ["sticky-1"])
    }

    let document = try await service.canvasWorkspaceDocument(
        id: workspace.id,
        principalKind: .agent,
        principalId: actor.id,
        isAdmin: false
    )
    #expect(document.revision == 2)
    #expect(document.elements.count == 1)
    #expect(document.elements.first?.data["text"] == .string("Moved"))
}

@Test
func builtinTemplateApplicationRemapsIDsAndPreservesExistingCanvas() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let workspace = try await service.createCanvasWorkspace(
        request: WorkspaceCreateRequest(title: "Template test"),
        ownerKind: .agent,
        ownerId: "agent-template"
    )
    let actor = WorkspaceActor(kind: .agent, id: "agent-template")
    _ = try await service.commitCanvasWorkspaceTransaction(
        workspaceId: workspace.id,
        request: WorkspaceTransactionRequest(
            id: "tx-existing",
            baseRevision: 0,
            operations: [
                WorkspaceOperation(kind: .createElement, element: makeElement(id: "existing", text: "Keep me")),
            ]
        ),
        actor: actor
    )
    let templates = await service.workspaceTemplates(principalId: actor.id)
    let template = try #require(templates.first(where: { $0.id == "brainstorming" }))

    _ = try await service.applyWorkspaceTemplate(
        workspaceId: workspace.id,
        templateId: template.id,
        actor: actor,
        isAdmin: false
    )
    let document = try await service.canvasWorkspaceDocument(
        id: workspace.id,
        principalKind: .agent,
        principalId: actor.id,
        isAdmin: false
    )

    #expect(document.elements.contains(where: { $0.id == "existing" }))
    #expect(document.elements.count == template.document.elements.count + 1)
    #expect(Set(document.elements.map(\.id)).count == document.elements.count)
    #expect(template.document.elements.allSatisfy { source in
        !document.elements.contains(where: { $0.id == source.id })
    })
}

@Test
func sqliteWorkspacePersistenceKeepsChildrenWhenMetadataRevisionUpdates() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-canvas-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/sloppy/Storage/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = SQLiteStore(
        path: root.appendingPathComponent("sloppy.sqlite").path,
        schemaSQL: schema
    )
    var workspace = WorkspaceRecord(id: "ws-sqlite", title: "SQLite", ownerId: "owner")
    let document = WorkspaceDocument(
        workspaceId: workspace.id,
        revision: 1,
        elements: [makeElement(id: "persisted", text: "Persisted", revision: 1)]
    )
    let member = WorkspaceMember(
        workspaceId: workspace.id,
        principalKind: .user,
        principalId: "owner",
        role: .owner
    )
    let transaction = WorkspaceCommittedTransaction(
        id: "tx-sqlite",
        workspaceId: workspace.id,
        revision: 1,
        actor: WorkspaceActor(kind: .user, id: "owner"),
        operations: [
            WorkspaceOperation(kind: .createElement, element: document.elements[0]),
        ],
        inverseOperations: [
            WorkspaceOperation(kind: .deleteElement, targetId: "persisted"),
        ]
    )

    await store.saveWorkspace(workspace)
    await store.saveWorkspaceDocument(document)
    await store.saveWorkspaceMember(member)
    await store.saveWorkspaceTransaction(transaction)
    workspace.revision = 1
    workspace.updatedAt = Date()
    await store.saveWorkspace(workspace)

    #expect(await store.workspaceDocument(id: workspace.id) == document)
    let storedMembers = await store.listWorkspaceMembers(workspaceId: workspace.id)
    #expect(storedMembers.count == 1)
    #expect(storedMembers.first?.principalId == member.principalId)
    #expect(storedMembers.first?.role == .owner)
    let storedTransactions = await store.listWorkspaceTransactions(workspaceId: workspace.id, afterRevision: 0)
    #expect(storedTransactions.count == 1)
    #expect(storedTransactions.first?.id == transaction.id)
    #expect(storedTransactions.first?.revision == transaction.revision)
}
