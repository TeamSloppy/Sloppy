import Foundation
import Protocols

enum SloppyTUIApprovalMode {
    static let options: [SessionApprovalMode] = [.askForApproval, .approveForMe]

    static func title(_ mode: SessionApprovalMode) -> String {
        switch mode {
        case .askForApproval: "Ask for approval"
        case .approveForMe: "Approve for me"
        }
    }

    static func detail(_ mode: SessionApprovalMode) -> String {
        switch mode {
        case .askForApproval: "Ask you before actions that require approval."
        case .approveForMe: "JEV reviews actions, with Visor as backup. Human decisions still come to you."
        }
    }
}

@MainActor
extension SloppyTUIScreen {
    var approvalModeKey: [String] {
        let backend: String
        if let remote = service as? RemoteSloppyTUIBackend {
            backend = "remote:\(remote.node.url)"
        } else if let mesh = service as? MeshSloppyTUIBackend {
            backend = "mesh:\(mesh.node.id)"
        } else {
            backend = runtime.configPath
        }
        return [backend, agent.id, session.id]
    }

    var approvalModeStatus: String {
        if approvalModeSavingKeys.contains(approvalModeKey) { return "Saving approvals..." }
        if let mode = approvalModes[approvalModeKey] { return SloppyTUIApprovalMode.title(mode) }
        return hasPersistedSession ? "Approvals: /approvals" : "Ask for approval"
    }

    @discardableResult
    func refreshApprovalMode(reportError: Bool = false) async -> Bool {
        let key = approvalModeKey
        if !hasPersistedSession {
            guard !draftApprovalModeOverrides.contains(key) else { return true }
            let load: Task<CoreConfig, Never>
            let revision: UUID
            if let pending = draftApprovalModeLoads[key], let pendingRevision = approvalModeRevisions[key] {
                load = pending
                revision = pendingRevision
            } else {
                revision = UUID()
                approvalModeRevisions[key] = revision
                let backend = service
                load = Task { await backend.getConfig() }
                draftApprovalModeLoads[key] = load
            }
            let config = await load.value
            if approvalModeRevisions[key] == revision { draftApprovalModeLoads[key] = nil }
            guard approvalModeKey == key, !hasPersistedSession,
                  approvalModeRevisions[key] == revision, !draftApprovalModeOverrides.contains(key) else { return false }
            approvalModes[key] = config.defaultChatApprovalMode ?? .askForApproval
            refreshStaticChrome()
            return true
        }
        guard !approvalModeSavingKeys.contains(key) else { return false }
        let revision = UUID()
        approvalModeRevisions[key] = revision
        do {
            let policy = try await service.getSessionApprovalPolicy(agentID: agent.id, sessionID: session.id)
            guard approvalModeKey == key, approvalModeRevisions[key] == revision else { return false }
            approvalModes[key] = policy.mode
            refreshStaticChrome()
            return true
        } catch {
            guard approvalModeKey == key, approvalModeRevisions[key] == revision else { return false }
            if reportError { appendLocalCard("Could not load approval mode: \(error.localizedDescription). Check that Sloppy Core supports chat approval modes.") }
            return false
        }
    }

    func showApprovalModePicker() async {
        guard await refreshApprovalMode(reportError: true) else { return }
        let mode = approvalModes[approvalModeKey] ?? .askForApproval
        activePicker = SloppyTUIPicker(
            kind: .approvalMode,
            title: "Chat approval mode",
            items: SloppyTUIApprovalMode.options.map {
                .init(value: $0.rawValue, label: SloppyTUIApprovalMode.title($0),
                      description: SloppyTUIApprovalMode.detail($0), isCurrent: $0 == mode)
            },
            selectedIndex: SloppyTUIApprovalMode.options.firstIndex(of: mode) ?? 0
        )
        refreshStaticChrome(statusLine: "select approval mode, Enter to save, Esc to cancel")
    }

    func selectApprovalMode(_ mode: SessionApprovalMode) async {
        let key = approvalModeKey
        guard !approvalModeSavingKeys.contains(key) else { return }
        guard hasPersistedSession else {
            draftApprovalModeOverrides.insert(key)
            approvalModes[key] = mode
            refreshStaticChrome()
            return
        }
        approvalModeRevisions[key] = UUID()
        approvalModeSavingKeys.insert(key)
        refreshStaticChrome()
        defer {
            approvalModeSavingKeys.remove(key)
            refreshStaticChrome()
        }
        do {
            let policy = try await service.setSessionApprovalPolicy(
                agentID: agent.id, sessionID: session.id, policy: .init(mode: mode)
            )
            approvalModes[key] = policy.mode
            pendingApprovalModes[key] = nil
        } catch {
            if approvalModeKey == key {
                appendLocalCard("Could not save approval mode: \(error.localizedDescription). The previous mode is still active.")
            }
        }
    }

    /// A draft policy must reach Core before its first message can run.
    func applyPendingApprovalMode() async throws {
        let key = approvalModeKey
        guard let mode = pendingApprovalModes[key] else { return }
        let policy = try await service.setSessionApprovalPolicy(
            agentID: agent.id, sessionID: session.id, policy: .init(mode: mode)
        )
        approvalModes[key] = policy.mode
        pendingApprovalModes[key] = nil
    }
}
