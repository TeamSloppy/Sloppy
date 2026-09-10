import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct MeshSettingsSection: View {
    let settings: ClientSettings

    @State private var inviteToken: String = ""
    @State private var statusMessage: String?
    @State private var hasError = false
    @State private var isConnecting = false
    @State private var isLoading = false
    @State private var nodes: [MeshNodeRecord] = []

    @Environment(\.theme) private var theme

    private var api: SloppyAPIClient {
        SloppyAPIClient(baseURL: settings.baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Join a mesh") {
                SettingsFieldRow("Invite token", hint: "Paste an invite beginning with slp_mesh_", text: $inviteToken)
                HStack {
                    Text("Connect this client to another machine.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button(action: acceptInvite) {
                        Label(isConnecting ? "Connecting…" : "Connect", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                    .accessibilityIdentifier("settings.mesh.connect")
                }
                .padding(16)
            }

            SettingsSectionCard("Connected nodes") {
                HStack {
                    Text("Choose the default node for this client.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button(action: refreshNodes) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || isConnecting)
                    .accessibilityIdentifier("settings.mesh.refresh")
                }
                .padding(16)

                SettingsDivider()
                if isLoading && nodes.isEmpty {
                    ProgressView("Discovering nodes…")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                } else if nodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No connected nodes")
                            .font(.system(size: 14, weight: .medium))
                        Text("Use an invite token above, or refresh to discover nodes.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    VStack(spacing: 4) {
                        ForEach(nodes) { node in
                            nodeRow(node)
                        }
                    }
                    .padding(8)
                }
            }

            if let statusMessage {
                Label(statusMessage, systemImage: hasError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(hasError ? Color.red : .secondary)
                    .textSelection(.enabled)
            }
        }
        .onAppear { refreshNodes() }
    }

    private func nodeRow(_ node: MeshNodeRecord) -> some View {
        let selected = node.id == settings.meshTargetNodeId
        return Button {
            settings.meshTargetNodeId = node.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(node.status == .online ? Color.green : .secondary)
                            .frame(width: 6, height: 6)
                        Text(node.status.rawValue.capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(12)
            .background(selected ? theme.colors.accent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(SettingsChoiceButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Set as the default mesh node")
        .accessibilityIdentifier("settings.mesh.node.\(node.id)")
    }

    private func acceptInvite() {
        let token = inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !isConnecting else { return }

        isConnecting = true
        hasError = false
        statusMessage = nil
        Task { @MainActor in
            defer { isConnecting = false }
            do {
                let node = try await api.acceptMeshInvite(token: token)
                settings.meshTargetNodeId = node.id
                inviteToken = ""
                statusMessage = "Connected as \(node.displayName)"
                refreshNodes()
            } catch {
                hasError = true
                statusMessage = error.localizedDescription
            }
        }
    }

    private func refreshNodes() {
        guard !isLoading else { return }
        isLoading = true
        hasError = false
        if !isConnecting { statusMessage = nil }

        Task { @MainActor in
            defer {
                isLoading = false
            }

            do {
                nodes = try await api.fetchMeshNodes()
                if settings.meshTargetNodeId == nil,
                   let first = nodes.first {
                    settings.meshTargetNodeId = first.id
                }
            } catch {
                hasError = true
                statusMessage = error.localizedDescription
            }
        }
    }
}
