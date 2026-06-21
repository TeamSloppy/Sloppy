import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct MeshSettingsSection: View {
    let settings: ClientSettings

    @State private var inviteToken: String = ""
    @State private var statusMessage: String = "Ready to connect to mesh"
    @State private var isLoading = false
    @State private var nodes: [MeshNodeRecord] = []

    @Environment(\.theme) private var theme

    private var api: SloppyAPIClient {
        SloppyAPIClient(baseURL: settings.baseURL)
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return SettingsSectionCard("Sloppy Mesh") {
            SettingsFieldRow("Invite Token", hint: "Paste slp_mesh_… token", text: $inviteToken)

            HStack(spacing: sp.s) {
                Button("CONNECT") {
                    acceptInvite()
                }
                .font(.system(size: 11))
                .foregroundColor(c.accent)

                Button("REFRESH NODES") {
                    refreshNodes()
                }
                .font(.system(size: 11))
                .foregroundColor(c.accent)
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)

            if isLoading {
                Text("Loading mesh nodes…")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else if nodes.isEmpty {
                Text("No mesh nodes discovered yet")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            } else {
                ForEach(nodes) { node in
                    Button {
                        settings.meshTargetNodeId = node.id
                        statusMessage = "Default mesh node: \(node.displayName)"
                    } label: {
                        HStack(spacing: sp.s) {
                            Text(node.displayName)
                                .font(.system(size: theme.typography.body))
                                .foregroundColor(c.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(node.status.rawValue)
                                .font(.system(size: theme.typography.micro))
                                .foregroundColor(node.status == .online ? c.statusDone : c.textMuted)

                            if node.id == settings.meshTargetNodeId {
                                Text("Selected")
                                    .font(.system(size: theme.typography.micro))
                                    .foregroundColor(c.accent)
                            }
                        }
                        .padding(.horizontal, sp.m)
                        .padding(.vertical, sp.s)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let selectedNodeId = settings.meshTargetNodeId,
               let selectedNode = nodes.first(where: { $0.id == selectedNodeId }) {
                Text("Default node: \(selectedNode.displayName)")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(c.textMuted)
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
            }

            Text(statusMessage)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
        }
        .padding(.horizontal, sp.m)
        .onAppear {
            refreshNodes()
        }
    }

    private func acceptInvite() {
        let token = inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        statusMessage = "Accepting invite..."
        Task { @MainActor in
            do {
                let node = try await api.acceptMeshInvite(token: token)
                settings.meshTargetNodeId = node.id
                statusMessage = "Connected as \(node.displayName)"
                refreshNodes()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func refreshNodes() {
        isLoading = true
        statusMessage = "Loading mesh nodes..."

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
                statusMessage = nodes.isEmpty ? "No mesh nodes discovered yet" : "Mesh nodes refreshed"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
