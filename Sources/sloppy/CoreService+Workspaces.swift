import Foundation
import Protocols

extension CoreService {
    func listCanvasWorkspaces(
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool,
        projectId: String? = nil,
        includeArchived: Bool = false
    ) async -> [WorkspaceRecord] {
        await waitForStartup()
        let all = await store.listWorkspaces()
        var allowedIds: Set<String> = []
        if !isAdmin {
            for workspace in all {
                let members = await store.listWorkspaceMembers(workspaceId: workspace.id)
                if members.contains(where: {
                    $0.principalKind == principalKind && $0.principalId == principalId
                }) {
                    allowedIds.insert(workspace.id)
                }
            }
        }
        return all.filter { workspace in
            (isAdmin || allowedIds.contains(workspace.id))
                && (includeArchived || !workspace.isArchived)
                && (projectId == nil || workspace.projectId == projectId)
        }
    }

    func createCanvasWorkspace(
        request: WorkspaceCreateRequest,
        ownerKind: WorkspacePrincipalKind,
        ownerId: String
    ) async throws -> WorkspaceRecord {
        await waitForStartup()
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else {
            throw WorkspaceError.invalidPayload
        }
        let projectId = normalizedOptional(request.projectId)
        if let projectId, await store.project(id: projectId) == nil {
            throw WorkspaceError.invalidPayload
        }
        let id = "ws-\(UUID().uuidString.lowercased())"
        let now = Date()
        let record = WorkspaceRecord(
            id: id,
            title: title,
            description: String((request.description ?? "").prefix(2_000)),
            ownerId: ownerId,
            projectId: projectId,
            createdAt: now,
            updatedAt: now
        )
        var document = WorkspaceDocument(workspaceId: id)
        if let templateId = normalizedOptional(request.templateId),
           let template = await workspaceTemplates(principalId: ownerId).first(where: { $0.id == templateId }) {
            document = remappedTemplateDocument(template.document, workspaceId: id)
        }
        await store.saveWorkspace(record)
        await store.saveWorkspaceDocument(document)
        await store.saveWorkspaceMember(WorkspaceMember(
            workspaceId: id,
            principalKind: ownerKind,
            principalId: ownerId,
            role: .owner
        ))
        return record
    }

    func getCanvasWorkspace(
        id: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> WorkspaceRecord {
        guard validWorkspaceId(id), let record = await store.workspace(id: id) else {
            throw WorkspaceError.notFound
        }
        let role = await workspaceRole(
            workspaceId: id,
            principalKind: principalKind,
            principalId: principalId
        )
        guard isAdmin || role != nil else {
            throw WorkspaceError.forbidden
        }
        return record
    }

    func updateCanvasWorkspace(
        id: String,
        request: WorkspaceUpdateRequest,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> WorkspaceRecord {
        var record = try await getCanvasWorkspace(
            id: id,
            principalKind: principalKind,
            principalId: principalId,
            isAdmin: isAdmin
        )
        let role = await workspaceRole(workspaceId: id, principalKind: principalKind, principalId: principalId)
        guard isAdmin || role == .owner || role == .editor else {
            throw WorkspaceError.forbidden
        }
        if let title = request.title {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 160 else {
                throw WorkspaceError.invalidPayload
            }
            record.title = normalized
        }
        if let description = request.description {
            record.description = String(description.prefix(2_000))
        }
        if let cover = request.cover {
            record.cover = normalizedOptional(cover)
        }
        if request.clearProject == true {
            record.projectId = nil
        } else if let projectId = normalizedOptional(request.projectId) {
            guard await store.project(id: projectId) != nil else {
                throw WorkspaceError.invalidPayload
            }
            record.projectId = projectId
        }
        record.updatedAt = Date()
        await store.saveWorkspace(record)
        return record
    }

    func archiveCanvasWorkspace(
        id: String,
        archived: Bool,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> WorkspaceRecord {
        var record = try await getCanvasWorkspace(
            id: id,
            principalKind: principalKind,
            principalId: principalId,
            isAdmin: isAdmin
        )
        let role = await workspaceRole(workspaceId: id, principalKind: principalKind, principalId: principalId)
        guard isAdmin || role == .owner else {
            throw WorkspaceError.forbidden
        }
        record.isArchived = archived
        record.updatedAt = Date()
        await store.saveWorkspace(record)
        return record
    }

    func canvasWorkspaceDocument(
        id: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> WorkspaceDocument {
        _ = try await getCanvasWorkspace(
            id: id,
            principalKind: principalKind,
            principalId: principalId,
            isAdmin: isAdmin
        )
        return await store.workspaceDocument(id: id) ?? WorkspaceDocument(workspaceId: id)
    }

    func canvasWorkspaceTransactions(
        id: String,
        afterRevision: Int,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> [WorkspaceCommittedTransaction] {
        _ = try await getCanvasWorkspace(
            id: id,
            principalKind: principalKind,
            principalId: principalId,
            isAdmin: isAdmin
        )
        return await store.listWorkspaceTransactions(workspaceId: id, afterRevision: afterRevision)
    }

    func commitCanvasWorkspaceTransaction(
        workspaceId: String,
        request: WorkspaceTransactionRequest,
        actor: WorkspaceActor,
        isAdmin: Bool = false
    ) async throws -> WorkspaceCommittedTransaction {
        let principalKind: WorkspacePrincipalKind = actor.kind == .agent ? .agent : .user
        let role = await workspaceRole(
            workspaceId: workspaceId,
            principalKind: principalKind,
            principalId: actor.id
        )
        do {
            return try await workspaceRealtimeService.commit(
                workspaceId: workspaceId,
                request: request,
                actor: actor,
                canEdit: isAdmin || role?.canEdit == true
            )
        } catch WorkspaceRealtimeService.WorkspaceRealtimeError.workspaceNotFound {
            throw WorkspaceError.notFound
        } catch WorkspaceRealtimeService.WorkspaceRealtimeError.forbidden {
            throw WorkspaceError.forbidden
        } catch WorkspaceRealtimeService.WorkspaceRealtimeError.conflict(let revision, let ids) {
            throw WorkspaceError.conflict(latestRevision: revision, elementIds: ids)
        } catch {
            throw WorkspaceError.invalidPayload
        }
    }

    func publishCanvasWorkspaceAgentStatus(
        workspaceId: String,
        agentId: String,
        status: String
    ) async {
        guard await workspaceRole(
            workspaceId: workspaceId,
            principalKind: .agent,
            principalId: agentId
        ) != nil else {
            return
        }
        await workspaceRealtimeService.publishAgentStatus(
            workspaceId: workspaceId,
            actor: WorkspaceActor(kind: .agent, id: agentId, displayName: agentId),
            status: String(status.prefix(200))
        )
    }

    func undoCanvasWorkspaceTransaction(
        workspaceId: String,
        transactionId: String,
        actor: WorkspaceActor,
        isAdmin: Bool = false
    ) async throws -> WorkspaceCommittedTransaction {
        guard let previous = await store.workspaceTransaction(
            workspaceId: workspaceId,
            transactionId: transactionId
        ) else {
            throw WorkspaceError.notFound
        }
        let document = await store.workspaceDocument(id: workspaceId)
            ?? WorkspaceDocument(workspaceId: workspaceId)
        let affectedIds = Set(previous.operations.compactMap { $0.element?.id ?? $0.targetId })
        let expected = Dictionary(uniqueKeysWithValues: document.elements
            .filter { affectedIds.contains($0.id) }
            .map { ($0.id, $0.revision) })
        return try await commitCanvasWorkspaceTransaction(
            workspaceId: workspaceId,
            request: WorkspaceTransactionRequest(
                id: "undo-\(UUID().uuidString.lowercased())",
                baseRevision: document.revision,
                expectedElementRevisions: expected,
                operations: previous.inverseOperations,
                summary: "Undo: \(previous.summary ?? previous.id)"
            ),
            actor: actor,
            isAdmin: isAdmin
        )
    }

    func createCanvasWorkspaceRealtimeTicket(
        workspaceId: String,
        actor: WorkspaceActor,
        isAdmin: Bool
    ) async throws -> WorkspaceRealtimeTicketResponse {
        let kind: WorkspacePrincipalKind = actor.kind == .agent ? .agent : .user
        let role = await workspaceRole(
            workspaceId: workspaceId,
            principalKind: kind,
            principalId: actor.id
        )
        guard let effectiveRole = isAdmin ? WorkspaceMemberRole.owner : role else {
            throw WorkspaceError.forbidden
        }
        return await workspaceRealtimeService.createTicket(
            workspaceId: workspaceId,
            actor: actor,
            role: effectiveRole
        )
    }

    func listCanvasWorkspaceMembers(
        workspaceId: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String,
        isAdmin: Bool
    ) async throws -> [WorkspaceMember] {
        _ = try await getCanvasWorkspace(
            id: workspaceId,
            principalKind: principalKind,
            principalId: principalId,
            isAdmin: isAdmin
        )
        return await store.listWorkspaceMembers(workspaceId: workspaceId)
    }

    func saveCanvasWorkspaceMember(
        _ member: WorkspaceMember,
        actorKind: WorkspacePrincipalKind,
        actorId: String,
        isAdmin: Bool
    ) async throws -> WorkspaceMember {
        let actorRole = await workspaceRole(
            workspaceId: member.workspaceId,
            principalKind: actorKind,
            principalId: actorId
        )
        guard isAdmin || actorRole == .owner else {
            throw WorkspaceError.forbidden
        }
        guard !member.principalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceError.invalidPayload
        }
        await store.saveWorkspaceMember(member)
        return member
    }

    func workspaceTemplates(principalId: String) async -> [WorkspaceTemplate] {
        let stored = await store.listWorkspaceTemplates()
        return Self.builtinWorkspaceTemplates + stored.filter {
            $0.visibility == .team || $0.ownerId == principalId
        }
    }

    func createWorkspaceTemplate(
        request: WorkspaceTemplateCreateRequest,
        ownerId: String
    ) async throws -> WorkspaceTemplate {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, request.visibility != .builtin else {
            throw WorkspaceError.invalidPayload
        }
        let template = WorkspaceTemplate(
            id: "template-\(UUID().uuidString.lowercased())",
            title: title,
            description: String(request.description.prefix(500)),
            category: String(request.category.prefix(80)),
            visibility: request.visibility,
            ownerId: ownerId,
            document: request.document
        )
        await store.saveWorkspaceTemplate(template)
        return template
    }

    func applyWorkspaceTemplate(
        workspaceId: String,
        templateId: String,
        actor: WorkspaceActor,
        isAdmin: Bool
    ) async throws -> WorkspaceCommittedTransaction {
        guard let template = await workspaceTemplates(principalId: actor.id)
            .first(where: { $0.id == templateId })
        else {
            throw WorkspaceError.notFound
        }
        let document = await store.workspaceDocument(id: workspaceId)
            ?? WorkspaceDocument(workspaceId: workspaceId)
        let fragment = remappedTemplateDocument(template.document, workspaceId: workspaceId)
        let operations = fragment.elements.map {
            WorkspaceOperation(kind: .createElement, element: $0)
        } + fragment.connections.map {
            WorkspaceOperation(kind: .createConnection, connection: $0)
        }
        return try await commitCanvasWorkspaceTransaction(
            workspaceId: workspaceId,
            request: WorkspaceTransactionRequest(
                id: "template-\(UUID().uuidString.lowercased())",
                baseRevision: document.revision,
                operations: operations,
                summary: "Apply template: \(template.title)"
            ),
            actor: actor,
            isAdmin: isAdmin
        )
    }

    func workspaceRole(
        workspaceId: String,
        principalKind: WorkspacePrincipalKind,
        principalId: String
    ) async -> WorkspaceMemberRole? {
        await store.listWorkspaceMembers(workspaceId: workspaceId)
            .first {
                $0.principalKind == principalKind && $0.principalId == principalId
            }?
            .role
    }

    private func remappedTemplateDocument(
        _ source: WorkspaceDocument,
        workspaceId: String
    ) -> WorkspaceDocument {
        let idMap = Dictionary(uniqueKeysWithValues: source.elements.map {
            ($0.id, "element-\(UUID().uuidString.lowercased())")
        })
        let elements = source.elements.map { sourceElement -> WorkspaceElement in
            var element = sourceElement
            element.id = idMap[sourceElement.id] ?? sourceElement.id
            element.parentId = sourceElement.parentId.flatMap { idMap[$0] }
            element.groupId = sourceElement.groupId.map { "group-\($0)-\(UUID().uuidString.prefix(6))" }
            element.revision = 0
            return element
        }
        let connections = source.connections.compactMap { sourceConnection -> WorkspaceConnection? in
            guard let sourceId = idMap[sourceConnection.sourceElementId],
                  let targetId = idMap[sourceConnection.targetElementId]
            else {
                return nil
            }
            var connection = sourceConnection
            connection.id = "connection-\(UUID().uuidString.lowercased())"
            connection.sourceElementId = sourceId
            connection.targetElementId = targetId
            connection.revision = 0
            return connection
        }
        return WorkspaceDocument(
            workspaceId: workspaceId,
            elements: elements,
            connections: connections
        )
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private func validWorkspaceId(_ value: String) -> Bool {
        value.range(of: #"^ws-[a-z0-9-]{1,80}$"#, options: .regularExpression) != nil
    }

    private static let builtinWorkspaceTemplates: [WorkspaceTemplate] = {
        let definitions: [(String, String, String, [String])] = [
            ("brainstorming", "Brainstorming", "Ideation board with themed sticky notes.", ["Ideas", "Questions", "Next steps"]),
            ("kanban", "Kanban", "Simple flow from backlog to done.", ["Backlog", "In progress", "Done"]),
            ("retrospective", "Retrospective", "Team reflection and action planning.", ["Went well", "Needs work", "Actions"]),
            ("mind-map", "Mind map", "A central topic with connected branches.", ["Main topic", "Branch A", "Branch B"]),
            ("project-planning", "Project planning", "Goals, milestones, risks, and owners.", ["Goals", "Milestones", "Risks"]),
            ("research-board", "Research board", "Evidence, insights, and open questions.", ["Sources", "Insights", "Questions"]),
            ("comparison-table", "Comparison table", "Structured alternatives and criteria.", ["Alternatives", "Criteria", "Decision"]),
        ]
        return definitions.map { id, title, description, labels in
            let elements = labels.enumerated().map { index, label in
                WorkspaceElement(
                    id: "\(id)-\(index)",
                    kind: index == 0 ? .frame : .sticky,
                    bounds: WorkspaceRect(
                        x: Double(index * 300),
                        y: index == 0 ? 0 : 120,
                        width: 260,
                        height: index == 0 ? 360 : 180
                    ),
                    zIndex: index,
                    style: ["color": .string(index == 0 ? "#1e293b" : "#d9f99d")],
                    data: ["text": .string(label)]
                )
            }
            return WorkspaceTemplate(
                id: id,
                title: title,
                description: description,
                category: "built-in",
                visibility: .builtin,
                document: WorkspaceDocument(workspaceId: "template-\(id)", elements: elements)
            )
        }
    }()
}
