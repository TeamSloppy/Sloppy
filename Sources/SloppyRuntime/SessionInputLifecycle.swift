import Foundation
import Protocols

/// Canonical input eligibility is derived from the complete journal, never the disposable inbox.
public enum SessionInputLifecycle {
    public struct State: Sendable, Equatable {
        public var latest: AgentInputTransition
        public var context: AgentInputContext
        public var owner: AgentInputOwner?
        public var wasAdmitted: Bool { owner != nil }
    }

    public static func validate(_ transition: AgentInputTransition) throws {
        guard transition.schemaVersion == 1,
              UUID(uuidString: transition.messageId) != nil,
              transition.fingerprint.count == 67,
              transition.fingerprint.hasPrefix("v1:") || transition.fingerprint.hasPrefix("v2:"),
              isDigest(String(transition.fingerprint.dropFirst(3))) else { throw invalid() }
        if let owner = transition.owner {
            guard !owner.runId.isEmpty, !owner.userTurnId.isEmpty, owner.generation >= 0 else { throw invalid() }
        }
        if transition.disposition == .admitted, transition.owner == nil { throw invalid() }
        if transition.disposition == .queued || transition.disposition == .recordedOnly {
            guard transition.owner == nil else { throw invalid() }
        }
        if transition.disposition == .queued, transition.delivery != .pending { throw invalid() }
        if transition.disposition == .cancelled || transition.disposition == .failed || transition.disposition == .recordedOnly {
            guard transition.delivery == .delivered else { throw invalid() }
        }
        if let context = transition.context {
            guard context.request.clientMessageId == transition.messageId,
                  context.request.attachments.count == context.attachments.count,
                  context.request.attachments.allSatisfy({ $0.contentBase64 == nil }),
                  Set(context.attachments.map(\.attachment.id)).count == context.attachments.count else { throw invalid() }
            if var source = context.sourceRequest {
                guard source.clientMessageId == transition.messageId,
                      source.attachments.allSatisfy({ $0.contentBase64 == nil }) else { throw invalid() }
                // Preparation may interpret an explicit mode command or narrow a peer conversation.
                // It cannot change the sender, attachments, model choice or other authority fields.
                source.content = context.request.content
                source.mode = context.request.mode
                guard source == context.request else { throw invalid() }
            }
            for binding in context.attachments {
                guard !binding.attachment.id.isEmpty,
                      binding.hadInlineData ? binding.sha256.map(isDigest) == true : binding.sha256 == nil else { throw invalid() }
            }
            guard (context.uiSubmission == nil) == (context.uiSnapshot == nil) else { throw invalid() }
        }
    }

    public static func states(in events: [AgentSessionEvent]) throws -> [String: State] {
        var result: [String: State] = [:]
        var users: [String: AgentSessionMessage] = [:]
        for event in events where !event.isHistorical {
            if let message = event.message, message.role == .user, users[message.id] == nil { users[message.id] = message }
            for transition in event.inputTransitions ?? [] {
                try validate(transition)
                guard let message = users[transition.messageId] else { throw invalid() }
                let acquiresOwner = result[transition.messageId]?.owner == nil && transition.owner != nil
                if var previous = result[transition.messageId] {
                    guard transition.fingerprint == previous.latest.fingerprint,
                          transition.context == nil else { throw invalid() }
                    if let owner = previous.owner {
                        guard transition.owner == owner else { throw invalid() }
                    } else if transition.disposition != .admitted, transition.owner != nil {
                        throw invalid()
                    }
                    if previous.latest.delivery == .delivered, transition.delivery != .delivered { throw invalid() }
                    switch previous.latest.disposition {
                    case .queued:
                        guard transition.disposition != .queued else { throw invalid() }
                    case .admitted:
                        guard [.admitted, .cancelled, .failed].contains(transition.disposition) else { throw invalid() }
                    case .cancelled, .failed, .recordedOnly:
                        guard transition == previous.latest else { throw invalid() }
                    }
                    previous.owner = previous.owner ?? transition.owner
                    previous.latest = transition
                    result[transition.messageId] = previous
                } else {
                    guard let context = transition.context,
                          transition.disposition == .queued || transition.disposition == .admitted || transition.disposition == .recordedOnly else { throw invalid() }
                    try validate(context, message: message)
                    result[transition.messageId] = .init(latest: transition, context: context, owner: transition.owner)
                }
                if transition.disposition == .admitted, let owner = transition.owner {
                    guard let metadata = event.runtimeMetadata,
                          metadata.runId == owner.runId, metadata.userTurnId == owner.userTurnId,
                          acquiresOwner ? metadata.generation == owner.generation : metadata.generation >= owner.generation,
                          metadata.inputMessageId == transition.messageId,
                          metadata.requestFingerprint == transition.fingerprint else { throw invalid() }
                }
            }
        }
        return result
    }

    private static func validate(_ context: AgentInputContext, message: AgentSessionMessage) throws {
        guard message.userId == nil || message.userId == context.request.userId,
              message.peerOrigin == context.peerOrigin,
              message.uiAction == context.uiSubmission,
              message.supportsA2UI == context.request.supportsA2UI,
              (message.sessionReferences ?? []) == SessionReferenceContext.references(for: context.request),
              message.segments.compactMap(\.attachment) == context.attachments.map(\.attachment) else { throw invalid() }
        // UI actions have a human-readable presentation; their semantic payload and
        // accepted surface are pinned separately, rather than inferred from that text.
        if context.uiSubmission == nil {
            let text = message.segments.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text == context.request.content.trimmingCharacters(in: .whitespacesAndNewlines) ||
                text == context.sourceRequest?.content.trimmingCharacters(in: .whitespacesAndNewlines) else { throw invalid() }
        }
    }

    /// This also accepts projected history whose transition rows were compacted. Validation occurs
    /// against the full journal before compaction; any surviving tag still prevents legacy fallback.
    public static func contextEvents(_ events: [AgentSessionEvent], canonical: [AgentSessionEvent]? = nil) -> [AgentSessionEvent] {
        let source = canonical ?? events
        var tagged: Set<String> = []
        var admitted: Set<String> = []
        for event in source where !event.isHistorical {
            for transition in event.inputTransitions ?? [] {
                tagged.insert(transition.messageId)
                if transition.owner != nil { admitted.insert(transition.messageId) }
            }
        }
        return events.filter { event in
            guard !event.isHistorical, let message = event.message, message.role == .user else { return true }
            return !tagged.contains(message.id) || admitted.contains(message.id)
        }
    }

    /// Model context uses prepared commands and semantic UI payloads; display text stays on disk.
    public static func modelContextEvents(_ events: [AgentSessionEvent], canonical: [AgentSessionEvent]? = nil) -> [AgentSessionEvent] {
        var content: [String: String] = [:]
        for event in canonical ?? events {
            for transition in event.inputTransitions ?? [] {
                guard let context = transition.context,
                      context.uiSubmission != nil || context.sourceRequest != nil else { continue }
                let id = event.message?.id ?? transition.messageId
                content[id] = context.request.content
            }
        }
        return contextEvents(events, canonical: canonical).map { event in
            guard let message = event.message, message.role == .user, let text = content[message.id] else { return event }
            var copy = event
            copy.message?.segments = [.init(kind: .text, text: text)] + message.segments.filter { $0.kind != .text }
            return copy
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func invalid() -> AgentSessionFileStore.StoreError { .invalidPayload }
}
