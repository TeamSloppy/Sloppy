import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct AccountPreferences: View {
    let service: WorkspaceService
    @State private var user: AuthUserProfile?
    @State private var name = ""
    @State private var avatar = ""
    @State private var description = ""
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user {
                Text("\(user.login) · \(user.role)").font(.system(size: 13))
                SettingsFieldRow("Name", text: $name)
                SettingsFieldRow("Avatar URL", text: $avatar)
                SettingsFieldRow("Description", text: $description)
                Button("Save profile") { save() }.disabled(busy)
            }
            Text(status).font(.system(size: 12)).textSelection(.enabled)
            Button("Reload profile") { load() }.disabled(busy)
        }.onAppear { load() }
    }
    private func load() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                let value = try await service.account(); user = value
                name = value.name; avatar = value.avatar ?? ""; description = value.description ?? ""; status = ""
            } catch { status = error.localizedDescription }
        }
    }
    private func save() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { user = try await service.updateAccount(name: name, avatar: avatar, description: description); status = "Profile saved" }
            catch { status = error.localizedDescription }
        }
    }
}

struct ApprovalPreferences: View {
    let service: WorkspaceService
    @State private var approvals: [ClientPendingApproval] = []
    @State private var users: [ClientAccessUser] = []
    @State private var status = ""
    @State private var busy = false
    @State private var removal: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Refresh") { load() }.disabled(busy)
            Text(status).font(.system(size: 12)).textSelection(.enabled)
            Text("Pending tool requests").font(.system(size: 18, weight: .semibold))
            if approvals.isEmpty { Text("No pending requests").font(.system(size: 13)) }
            ForEach(approvals) { item in
                SettingsSectionCard(item.tool ?? item.id) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.reason ?? "Approval requested").textSelection(.enabled)
                        Text([item.agentId, item.sessionId].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 11))
                        HStack {
                            Button("Allow once") { decide(item, approved: true) }.disabled(busy)
                            Button("Reject") { decide(item, approved: false) }.disabled(busy)
                        }
                    }.padding(14)
                }
            }
            Text("Channel access users").font(.system(size: 18, weight: .semibold))
            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(user.displayName) · \(user.status)")
                    Text("\(user.platform) · \(user.platformUserId)").font(.system(size: 12))
                    if removal == user.id {
                        HStack {
                            Button("Confirm removal") { remove(user) }.disabled(busy)
                            Button("Cancel") { removal = nil }
                        }
                    } else { Button("Remove access") { removal = user.id } }
                }.padding(12)
            }
        }.onAppear { load() }
    }
    private func load() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            var failures: [String] = []
            do { approvals = try await service.pendingApprovals() } catch { failures.append(error.localizedDescription) }
            do { users = try await service.accessUsers() } catch { failures.append(error.localizedDescription) }
            status = failures.joined(separator: "\n")
        }
    }
    private func decide(_ approval: ClientPendingApproval, approved: Bool) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await service.decideApproval(id: approval.id, approved: approved); approvals.removeAll { $0.id == approval.id }; status = "Decision saved" }
            catch { status = error.localizedDescription }
        }
    }
    private func remove(_ user: ClientAccessUser) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await service.removeAccessUser(id: user.id); users.removeAll { $0.id == user.id }; removal = nil }
            catch { status = error.localizedDescription }
        }
    }
}
