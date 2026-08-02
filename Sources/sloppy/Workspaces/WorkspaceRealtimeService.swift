import Foundation
import Protocols

actor WorkspaceRealtimeService {
    struct TicketContext: Sendable {
        let workspaceId: String
        let actor: WorkspaceActor
        let role: WorkspaceMemberRole
        let expiresAt: Date
    }

    enum WorkspaceRealtimeError: Error, Equatable {
        case invalidTransaction
        case workspaceNotFound
        case forbidden
        case conflict(latestRevision: Int, elementIds: [String])
    }

    private let store: any PersistenceStore
    private var subscribers: [String: [UUID: AsyncStream<WorkspaceRealtimeMessage>.Continuation]] = [:]
    private var tickets: [String: TicketContext] = [:]

    init(store: any PersistenceStore) {
        self.store = store
    }

    func createTicket(
        workspaceId: String,
        actor: WorkspaceActor,
        role: WorkspaceMemberRole
    ) -> WorkspaceRealtimeTicketResponse {
        pruneExpiredTickets()
        let ticket = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let expiresAt = Date().addingTimeInterval(30)
        tickets[ticket] = TicketContext(
            workspaceId: workspaceId,
            actor: actor,
            role: role,
            expiresAt: expiresAt
        )
        return WorkspaceRealtimeTicketResponse(ticket: ticket, expiresAt: expiresAt)
    }

    func consumeTicket(_ ticket: String, workspaceId: String) -> TicketContext? {
        pruneExpiredTickets()
        guard let context = tickets.removeValue(forKey: ticket),
              context.workspaceId == workspaceId,
              context.expiresAt > Date()
        else {
            return nil
        }
        return context
    }

    func subscribe(
        workspaceId: String,
        afterRevision: Int
    ) async throws -> AsyncStream<WorkspaceRealtimeMessage> {
        guard await store.workspace(id: workspaceId) != nil else {
            throw WorkspaceRealtimeError.workspaceNotFound
        }
        let document = await store.workspaceDocument(id: workspaceId)
            ?? WorkspaceDocument(workspaceId: workspaceId)
        let transactions = await store.listWorkspaceTransactions(
            workspaceId: workspaceId,
            afterRevision: afterRevision
        )
        let subscriberId = UUID()
        return AsyncStream { continuation in
            var workspaceSubscribers = subscribers[workspaceId] ?? [:]
            workspaceSubscribers[subscriberId] = continuation
            subscribers[workspaceId] = workspaceSubscribers
            continuation.yield(WorkspaceRealtimeMessage(
                kind: .ready,
                document: afterRevision == document.revision ? nil : document,
                transactions: transactions,
                latestRevision: document.revision
            ))
            continuation.onTermination = { [subscriberId, workspaceId] _ in
                Task {
                    await self.unsubscribe(workspaceId: workspaceId, subscriberId: subscriberId)
                }
            }
        }
    }

    func commit(
        workspaceId: String,
        request: WorkspaceTransactionRequest,
        actor: WorkspaceActor,
        canEdit: Bool
    ) async throws -> WorkspaceCommittedTransaction {
        guard canEdit else {
            throw WorkspaceRealtimeError.forbidden
        }
        guard !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.operations.isEmpty,
              request.operations.count <= 500
        else {
            throw WorkspaceRealtimeError.invalidTransaction
        }
        guard var workspace = await store.workspace(id: workspaceId) else {
            throw WorkspaceRealtimeError.workspaceNotFound
        }
        if let existing = await store.workspaceTransaction(
            workspaceId: workspaceId,
            transactionId: request.id
        ) {
            return existing
        }

        var document = await store.workspaceDocument(id: workspaceId)
            ?? WorkspaceDocument(workspaceId: workspaceId)
        let elementById = Dictionary(uniqueKeysWithValues: document.elements.map { ($0.id, $0) })
        let conflicts = request.expectedElementRevisions.compactMap { id, expected -> String? in
            guard let element = elementById[id], element.revision == expected else {
                return id
            }
            return nil
        }.sorted()
        guard conflicts.isEmpty else {
            throw WorkspaceRealtimeError.conflict(
                latestRevision: document.revision,
                elementIds: conflicts
            )
        }

        let nextRevision = max(workspace.revision, document.revision) + 1
        var inverse: [WorkspaceOperation] = []
        do {
            for operation in request.operations {
                let generatedInverse = try apply(
                    operation,
                    to: &document,
                    revision: nextRevision,
                    expectedElementRevisions: request.expectedElementRevisions
                )
                inverse.insert(contentsOf: generatedInverse.reversed(), at: 0)
            }
        } catch {
            throw WorkspaceRealtimeError.invalidTransaction
        }
        document.revision = nextRevision
        workspace.revision = nextRevision
        workspace.updatedAt = Date()
        let committedOperations = request.operations.map {
            canonicalOperation($0, in: document)
        }
        let committed = WorkspaceCommittedTransaction(
            id: request.id,
            workspaceId: workspaceId,
            revision: nextRevision,
            actor: actor,
            operations: committedOperations,
            inverseOperations: inverse,
            summary: request.summary,
            createdAt: workspace.updatedAt
        )

        await store.saveWorkspaceDocument(document)
        await store.saveWorkspaceTransaction(committed)
        await store.saveWorkspace(workspace)
        broadcast(
            WorkspaceRealtimeMessage(
                kind: .transactionCommitted,
                transaction: committed,
                latestRevision: nextRevision
            ),
            workspaceId: workspaceId
        )
        return committed
    }

    private func canonicalOperation(
        _ operation: WorkspaceOperation,
        in document: WorkspaceDocument
    ) -> WorkspaceOperation {
        switch operation.kind {
        case .createElement, .updateElement, .moveElement, .resizeElement, .groupElement,
             .ungroupElement, .assignFrame, .reorderElement:
            guard let id = operation.element?.id,
                  let element = document.elements.first(where: { $0.id == id })
            else {
                return operation
            }
            return WorkspaceOperation(kind: operation.kind, element: element)
        case .createConnection, .connect, .updateConnection:
            guard let id = operation.connection?.id,
                  let connection = document.connections.first(where: { $0.id == id })
            else {
                return operation
            }
            return WorkspaceOperation(kind: operation.kind, connection: connection)
        case .deleteElement, .deleteConnection, .disconnect:
            return operation
        }
    }

    func publishPresence(_ presence: WorkspacePresence, workspaceId: String) {
        broadcast(
            WorkspaceRealtimeMessage(kind: .presence, presence: presence),
            workspaceId: workspaceId
        )
    }

    func publishAgentStatus(
        workspaceId: String,
        actor: WorkspaceActor,
        status: String
    ) {
        broadcast(
            WorkspaceRealtimeMessage(
                kind: .agentStatus,
                presence: WorkspacePresence(actor: actor, status: status),
                message: status
            ),
            workspaceId: workspaceId
        )
    }

    private func apply(
        _ operation: WorkspaceOperation,
        to document: inout WorkspaceDocument,
        revision: Int,
        expectedElementRevisions: [String: Int]
    ) throws -> [WorkspaceOperation] {
        switch operation.kind {
        case .createElement:
            guard var element = operation.element,
                  validElementId(element.id),
                  !document.elements.contains(where: { $0.id == element.id })
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            element = normalized(element, revision: revision)
            document.elements.append(element)
            return [WorkspaceOperation(kind: .deleteElement, targetId: element.id)]

        case .updateElement, .moveElement, .resizeElement, .groupElement,
             .ungroupElement, .assignFrame, .reorderElement:
            guard var replacement = operation.element,
                  let index = document.elements.firstIndex(where: { $0.id == replacement.id }),
                  expectedElementRevisions[replacement.id] != nil
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            let previous = document.elements[index]
            replacement = normalized(replacement, revision: revision)
            document.elements[index] = replacement
            return [WorkspaceOperation(kind: .updateElement, element: previous)]

        case .deleteElement:
            guard let targetId = operation.targetId,
                  expectedElementRevisions[targetId] != nil,
                  let index = document.elements.firstIndex(where: { $0.id == targetId })
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            let previous = document.elements.remove(at: index)
            let removedConnections = document.connections.filter {
                $0.sourceElementId == targetId || $0.targetElementId == targetId
            }
            document.connections.removeAll {
                $0.sourceElementId == targetId || $0.targetElementId == targetId
            }
            return [WorkspaceOperation(kind: .createElement, element: previous)]
                + removedConnections.map { WorkspaceOperation(kind: .createConnection, connection: $0) }

        case .createConnection, .connect:
            guard var connection = operation.connection,
                  validElementId(connection.id),
                  !document.connections.contains(where: { $0.id == connection.id }),
                  document.elements.contains(where: { $0.id == connection.sourceElementId }),
                  document.elements.contains(where: { $0.id == connection.targetElementId })
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            connection.revision = revision
            document.connections.append(connection)
            return [WorkspaceOperation(kind: .deleteConnection, targetId: connection.id)]

        case .updateConnection:
            guard var replacement = operation.connection,
                  let index = document.connections.firstIndex(where: { $0.id == replacement.id }),
                  document.elements.contains(where: { $0.id == replacement.sourceElementId }),
                  document.elements.contains(where: { $0.id == replacement.targetElementId })
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            let previous = document.connections[index]
            replacement.revision = revision
            document.connections[index] = replacement
            return [WorkspaceOperation(kind: .updateConnection, connection: previous)]

        case .deleteConnection, .disconnect:
            guard let targetId = operation.targetId,
                  let index = document.connections.firstIndex(where: { $0.id == targetId })
            else {
                throw WorkspaceRealtimeError.invalidTransaction
            }
            let previous = document.connections.remove(at: index)
            return [WorkspaceOperation(kind: .createConnection, connection: previous)]
        }
    }

    private func normalized(_ element: WorkspaceElement, revision: Int) -> WorkspaceElement {
        var copy = element
        copy.bounds.x = finite(copy.bounds.x, fallback: 0)
        copy.bounds.y = finite(copy.bounds.y, fallback: 0)
        copy.bounds.width = max(40, finite(copy.bounds.width, fallback: 240))
        copy.bounds.height = max(40, finite(copy.bounds.height, fallback: 160))
        copy.rotation = finite(copy.rotation, fallback: 0)
        copy.revision = revision
        return copy
    }

    private func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private func validElementId(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func broadcast(_ message: WorkspaceRealtimeMessage, workspaceId: String) {
        for continuation in subscribers[workspaceId]?.values ?? [:].values {
            continuation.yield(message)
        }
    }

    private func unsubscribe(workspaceId: String, subscriberId: UUID) {
        subscribers[workspaceId]?[subscriberId] = nil
        if subscribers[workspaceId]?.isEmpty == true {
            subscribers[workspaceId] = nil
        }
    }

    private func pruneExpiredTickets() {
        let now = Date()
        tickets = tickets.filter { $0.value.expiresAt > now }
    }
}
