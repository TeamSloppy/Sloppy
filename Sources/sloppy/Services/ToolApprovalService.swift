import Foundation
import AgentRuntime
import Protocols

enum ToolApprovalWaitResult: Sendable, Equatable {
    case approved(ToolApprovalRecord)
    case rejected(ToolApprovalRecord)
    case timedOut(ToolApprovalRecord)
}

struct ToolApprovalBinding: Codable, Sendable, Equatable {
    var invocation: AgentRunMetadata
    var authorityDigest: String
    var requiredGrants: [ToolApprovalGrant]
    var authority: JSONValue? = nil

    func matches(_ current: Self) -> Bool {
        invocation == current.invocation && authorityDigest == current.authorityDigest &&
            requiredGrants.allSatisfy { current.requiredGrants.contains($0) }
    }
}

actor ToolApprovalService {
    private struct DurableApprovals: Codable {
        var version = 1
        var records: [ToolApprovalRecord]
        var bindings: [String: ToolApprovalBinding]? = nil
    }
    private struct PendingApproval {
        var record: ToolApprovalRecord
        var continuations: [CheckedContinuation<ToolApprovalWaitResult, Never>]
        var requestPublished: Bool
        var presentationStarted = false
    }

    static let defaultTimeoutSeconds: TimeInterval = 600

    private let eventBus: EventBus
    private let notificationService: NotificationService
    private var pending: [String: PendingApproval] = [:]
    private var expirationTasks: [String: Task<Void, Never>] = [:]
    private var resolvedBeforeWait: [String: ToolApprovalRecord] = [:]
    private let isoFormatter = ISO8601DateFormatter()
    private let persistenceURL: URL?
    private var persistenceLease: FileOwnershipLease?
    nonisolated let hasExclusivePersistenceOwnership: Bool
    private var durableRecords: [String: ToolApprovalRecord] = [:]
    private var durableBindings: [String: ToolApprovalBinding] = [:]
    private var persistenceUnavailable = false
    private var loadedExpirationsStarted = false

    init(eventBus: EventBus, notificationService: NotificationService, persistenceURL: URL? = nil,
        ownershipReference: FileOwnershipLease.Reference? = nil) {
        self.eventBus = eventBus
        self.notificationService = notificationService
        self.persistenceURL = persistenceURL
        if let persistenceURL {
            do {
                persistenceLease = try FileOwnershipLease.acquire(at: persistenceURL.appendingPathExtension("owner.lock"))
                hasExclusivePersistenceOwnership = true
                if let persistenceLease { ownershipReference?.bind(persistenceLease) }
            } catch { hasExclusivePersistenceOwnership = false; persistenceUnavailable = true; return }
        } else { hasExclusivePersistenceOwnership = true }
        if let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path) {
            do {
                let saved = try JSONDecoder().decode(DurableApprovals.self, from: Data(contentsOf: persistenceURL))
                guard saved.version == 1, Set(saved.records.map(\.id)).count == saved.records.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for var record in saved.records {
                    guard !record.id.isEmpty, !record.tool.isEmpty, record.expiresAt.timeIntervalSince1970.isFinite else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    if record.expiresAt <= Date(), record.status == .pending || record.status == .approved {
                        record.status = .timedOut
                        record.updatedAt = record.expiresAt
                        record.decisionReason = "The saved invocation's approval deadline expired."
                    }
                    durableRecords[record.id] = record
                    if record.status == .pending {
                        pending[record.id] = .init(record: record, continuations: [], requestPublished: true)
                    } else { resolvedBeforeWait[record.id] = record }
                }
                durableBindings = saved.bindings ?? [:]
                guard Set(durableBindings.keys).isSubset(of: Set(durableRecords.keys)) else { throw CocoaError(.fileReadCorruptFile) }
            } catch {
                // A corrupt/future approval store is never interpreted as a fresh grant store.
                pending = [:]; durableRecords = [:]; durableBindings = [:]; resolvedBeforeWait = [:]
                persistenceUnavailable = true
            }
        }
    }

    func currentOwnershipLease() -> FileOwnershipLease? {
        persistenceUnavailable ? nil : persistenceLease
    }

    /// Stop local waiters without erasing durable pending requests needed by a successor.
    func closePersistence() {
        persistenceUnavailable = true
        for task in expirationTasks.values { task.cancel() }
        expirationTasks.removeAll()
        loadedExpirationsStarted = true
        for entry in pending.values {
            var record = entry.record
            record.status = .rejected
            record.decisionReason = "The approval storage owner stopped."
            for waiter in entry.continuations { waiter.resume(returning: .rejected(record)) }
        }
        pending.removeAll()
        resolvedBeforeWait.removeAll()
        // Outstanding generations/effects retain the lease through their final factual write.
        persistenceLease = nil
    }

    func listPending(includeUnpublished: Bool = false) -> [ToolApprovalRecord] {
        startLoadedExpirations()
        return pending.values
            .filter { includeUnpublished || $0.requestPublished }
            .map(\.record)
            .filter { $0.status == .pending && $0.expiresAt > Date() }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func createPending(
        agentId: String,
        sessionId: String?,
        displaySessionId: String? = nil,
        channelId: String?,
        topicId: String?,
        toolCallId: String? = nil,
        request: ToolInvocationRequest,
        approvalKind: ToolApprovalKind? = nil,
        grants: [ToolApprovalGrant] = [],
        requestedBy: String? = nil,
        timeoutSeconds: TimeInterval = ToolApprovalService.defaultTimeoutSeconds,
        publishRequest: Bool = true,
        binding: ToolApprovalBinding? = nil
    ) async -> ToolApprovalRecord {
        startLoadedExpirations()
        if !persistenceUnavailable, let binding, let existing = durableRecords.values.first(where: {
            $0.agentId == agentId && $0.sessionId == sessionId &&
                durableBindings[$0.id]?.invocation.callEventId == binding.invocation.callEventId
        }), let original = durableBindings[existing.id] {
            if original.matches(binding), existing.tool == request.tool, existing.arguments == request.arguments,
               existing.grants == grants, existing.approvalKind == approvalKind {
                return existing
            }
            var rejected = existing
            rejected.id = UUID().uuidString; rejected.status = .rejected
            let authorityFields = Set(original.authority?.asObject?.keys.map { $0 } ?? [])
                .union(binding.authority?.asObject?.keys.map { $0 } ?? []).sorted().filter {
                    original.authority?.asObject?[$0] != binding.authority?.asObject?[$0]
                }
            let changes = [original.invocation == binding.invocation ? nil : "invocation",
                original.authorityDigest == binding.authorityDigest ? nil : "authority:" + authorityFields.joined(separator: ","),
                existing.arguments == request.arguments ? nil : "arguments",
                existing.grants == grants ? nil : "grants", existing.approvalKind == approvalKind ? nil : "kind"].compactMap { $0 }
            rejected.decisionReason = "The original approval does not authorize changed fields: " + changes.joined(separator: "; ")
            NSLog("approval.binding_rejected %@", changes.joined(separator: "; "))
            resolvedBeforeWait[rejected.id] = rejected
            return rejected
        }
        let now = Date()
        let record = ToolApprovalRecord(
            approvalKind: approvalKind,
            agentId: agentId,
            sessionId: sessionId,
            displaySessionId: displaySessionId,
            channelId: channelId,
            topicId: topicId,
            toolCallId: toolCallId ?? binding?.invocation.callEventId,
            tool: request.tool,
            arguments: request.arguments,
            grants: grants,
            reason: request.reason,
            requestedBy: requestedBy,
            createdAt: now,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(timeoutSeconds)
        )
        guard persist(record, binding: binding) else {
            var rejected = record
            rejected.status = .rejected
            rejected.decisionReason = "Approval storage is unavailable. The invocation was not authorized."
            resolvedBeforeWait[record.id] = rejected
            return rejected
        }
        pending[record.id] = PendingApproval(record: record, continuations: [], requestPublished: false)
        expirationTasks[record.id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, record.expiresAt.timeIntervalSinceNow))) }
            catch { return }
            _ = await self?.timeout(id: record.id)
        }
        if publishRequest { await publishPendingRequest(id: record.id) }
        return record
    }

    func publishPendingRequest(id: String) async {
        guard var entry = pending[id], entry.record.status == .pending, !entry.requestPublished else { return }
        guard entry.record.expiresAt > Date() else {
            _ = await timeout(id: id)
            return
        }
        entry.requestPublished = true
        pending[id] = entry
        let record = entry.record
        await emit(record: record, messageType: .toolApprovalRequested)
        await notificationService.pushToolApproval(record)
    }

    func claimPresentation(id: String) -> Bool {
        guard var entry = pending[id], entry.record.expiresAt > Date(), !entry.presentationStarted else { return false }
        entry.presentationStarted = true
        pending[id] = entry
        return true
    }

    func waitForDecision(id: String, timeoutSeconds: TimeInterval = ToolApprovalService.defaultTimeoutSeconds) async -> ToolApprovalWaitResult {
        guard !persistenceUnavailable else {
            return .rejected(.init(id: id, status: .rejected, agentId: "", tool: "", expiresAt: Date()))
        }
        startLoadedExpirations()
        if Task.isCancelled { return await cancelWait(id: id) }
        if let existing = pending[id]?.record, existing.status != .pending {
            return waitResult(for: existing)
        }
        if let resolved = resolvedBeforeWait.removeValue(forKey: id) {
            return waitResult(for: resolved)
        }
        if let saved = durableRecords[id], saved.status != .pending { return waitResult(for: saved) }

        let remaining = pending[id]?.record.expiresAt.timeIntervalSinceNow ?? 0
        let waitTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, min(timeoutSeconds, remaining)))) }
            catch { return }
            _ = await self?.timeout(id: id)
        }
        defer { waitTimeout.cancel() }

        return await withTaskCancellationHandler {
            if Task.isCancelled { return await cancelWait(id: id) }
            return await withPlatformCheckedContinuation { continuation in
                // Cancellation or a decision may have won before waiter registration.
                if let resolved = resolvedBeforeWait.removeValue(forKey: id) {
                    continuation.resume(returning: waitResult(for: resolved))
                    return
                }
                guard var entry = pending[id] else {
                    continuation.resume(returning: .timedOut(ToolApprovalRecord(
                        id: id,
                        status: .timedOut,
                        agentId: "",
                        tool: "",
                        expiresAt: Date()
                    )))
                    return
                }
                if entry.record.status != .pending {
                    continuation.resume(returning: waitResult(for: entry.record))
                    return
                }
                entry.continuations.append(continuation)
                pending[id] = entry
            }
        } onCancel: {
            Task { _ = await self.cancelWait(id: id) }
        }
    }

    private func cancelWait(id: String) async -> ToolApprovalWaitResult {
        if let record = await resolve(id: id, status: .rejected, decidedBy: "runtime",
            decisionReason: "The invocation was cancelled before approval.") {
            return .rejected(record)
        }
        if let resolved = resolvedBeforeWait[id] { return waitResult(for: resolved) }
        return .rejected(.init(id: id, status: .rejected, agentId: "", tool: "", expiresAt: Date()))
    }

    func approve(id: String, decidedBy: String?, decisionReason: String? = nil) async -> ToolApprovalRecord? {
        await resolve(id: id, status: .approved, decidedBy: decidedBy, decisionReason: decisionReason)
    }

    func reject(id: String, decidedBy: String?, decisionReason: String? = nil) async -> ToolApprovalRecord? {
        await resolve(id: id, status: .rejected, decidedBy: decidedBy, decisionReason: decisionReason)
    }

    @discardableResult
    func timeout(id: String) async -> ToolApprovalRecord? {
        await resolve(id: id, status: .timedOut, decidedBy: nil, decisionReason: nil)
    }

    private func resolve(
        id: String,
        status: ToolApprovalStatus,
        decidedBy: String?,
        decisionReason: String?
    ) async -> ToolApprovalRecord? {
        guard var entry = pending[id], entry.record.status == .pending else {
            return pending[id]?.record
        }

        // A late reviewer or UI response must never authorize an expired call.
        if status != .timedOut, entry.record.expiresAt <= Date() {
            _ = await timeout(id: id)
            return nil
        }
        expirationTasks.removeValue(forKey: id)?.cancel()

        entry.record.status = status
        entry.record.decidedBy = decidedBy
        entry.record.decisionReason = decisionReason
        entry.record.updatedAt = Date()
        guard persist(entry.record) else { return nil }
        pending[id] = entry

        let result = waitResult(for: entry.record)
        let continuations = entry.continuations
        if continuations.isEmpty {
            resolvedBeforeWait[id] = entry.record
            if resolvedBeforeWait.count > 256,
               let oldestID = resolvedBeforeWait.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key
            {
                resolvedBeforeWait.removeValue(forKey: oldestID)
            }
        }
        pending[id]?.continuations.removeAll()
        if status != .pending {
            pending.removeValue(forKey: id)
        }
        for continuation in continuations {
            continuation.resume(returning: result)
        }

        await emit(record: entry.record, messageType: .toolApprovalResolved)
        await notificationService.pushToolApproval(entry.record)
        return entry.record
    }

    private func waitResult(for record: ToolApprovalRecord) -> ToolApprovalWaitResult {
        if record.status == .approved, record.expiresAt <= Date() {
            var expired = record; expired.status = .timedOut
            return .timedOut(expired)
        }
        switch record.status {
        case .approved:
            return .approved(record)
        case .rejected:
            return .rejected(record)
        case .pending, .timedOut:
            return .timedOut(record)
        }
    }

    private func startLoadedExpirations() {
        guard !loadedExpirationsStarted else { return }
        loadedExpirationsStarted = true
        for (id, entry) in pending {
            let deadline = entry.record.expiresAt
            expirationTasks[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
                catch { return }
                _ = await self?.timeout(id: id)
            }
        }
    }

    /// Commit before publishing or resuming a waiter. Failed writes revoke every pending permit.
    private func persist(_ record: ToolApprovalRecord, binding: ToolApprovalBinding? = nil) -> Bool {
        guard !persistenceUnavailable else { return false }
        var candidate = durableRecords
        var bindings = durableBindings
        candidate[record.id] = record
        if let binding { bindings[record.id] = binding }
        let resolved = candidate.values.filter { $0.status != .pending }.sorted { $0.updatedAt > $1.updatedAt }
        for old in resolved.dropFirst(1_024) { candidate.removeValue(forKey: old.id); bindings.removeValue(forKey: old.id) }
        guard let persistenceURL else { durableRecords = candidate; durableBindings = bindings; return true }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(DurableApprovals(records: candidate.values.sorted { $0.id < $1.id }, bindings: bindings))
            try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: persistenceURL, options: .atomic)
            let handle = try FileHandle(forWritingTo: persistenceURL)
            defer { try? handle.close() }
            try handle.synchronize()
            durableRecords = candidate
            durableBindings = bindings
            return true
        } catch {
            persistenceUnavailable = true
            let abandoned = pending
            pending.removeAll()
            for task in expirationTasks.values { task.cancel() }
            expirationTasks.removeAll()
            for (id, entry) in abandoned {
                var rejected = entry.record
                rejected.status = .rejected
                rejected.decisionReason = "Approval storage failed before authorization was committed."
                resolvedBeforeWait[id] = rejected
                for waiter in entry.continuations { waiter.resume(returning: .rejected(rejected)) }
            }
            return false
        }
    }

    private func emit(record: ToolApprovalRecord, messageType: MessageType) async {
        var payload: [String: JSONValue] = [
            "approvalId": .string(record.id),
            "status": .string(record.status.rawValue),
            "agentId": .string(record.agentId),
            "tool": .string(record.tool),
            "arguments": .object(record.arguments),
            "grants": .array(record.grants.map { grant in
                var object: [String: JSONValue] = [
                    "kind": .string(grant.kind.rawValue),
                    "tool": .string(grant.tool)
                ]
                if let operation = grant.operation { object["operation"] = .string(operation) }
                if let resource = grant.resource { object["resource"] = .string(resource) }
                return .object(object)
            }),
            "createdAt": .string(isoFormatter.string(from: record.createdAt)),
            "updatedAt": .string(isoFormatter.string(from: record.updatedAt)),
            "expiresAt": .string(isoFormatter.string(from: record.expiresAt))
        ]
        if let approvalKind = record.approvalKind { payload["approvalKind"] = .string(approvalKind.rawValue) }
        if let sessionId = record.sessionId { payload["sessionId"] = .string(sessionId) }
        if let displaySessionId = record.displaySessionId { payload["displaySessionId"] = .string(displaySessionId) }
        if let channelId = record.channelId { payload["channelId"] = .string(channelId) }
        if let topicId = record.topicId { payload["topicId"] = .string(topicId) }
        if let toolCallId = record.toolCallId { payload["toolCallId"] = .string(toolCallId) }
        if let reason = record.reason { payload["reason"] = .string(reason) }
        if let requestedBy = record.requestedBy { payload["requestedBy"] = .string(requestedBy) }
        if let decidedBy = record.decidedBy { payload["decidedBy"] = .string(decidedBy) }
        if let decisionReason = record.decisionReason { payload["decisionReason"] = .string(decisionReason) }

        await eventBus.publish(EventEnvelope(
            messageType: messageType,
            channelId: record.channelId ?? record.displaySessionId ?? record.sessionId ?? "agent:\(record.agentId)",
            payload: .object(payload)
        ))
    }
}
