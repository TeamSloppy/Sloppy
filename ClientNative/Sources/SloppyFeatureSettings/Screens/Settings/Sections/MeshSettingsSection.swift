import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct MeshSettingsSection: View {
    let settings: ClientSettings
    private let apiClient: SloppyAPIClient?

    init(settings: ClientSettings, apiClient: SloppyAPIClient? = nil) {
        self.settings = settings
        self.apiClient = apiClient
    }

    @State private var inviteToken: String = ""
    @State private var statusMessage: String?
    @State private var hasError = false
    @State private var isConnecting = false
    @State private var isLoading = false
    @State private var nodes: [MeshNodeRecord] = []

    @Environment(\.theme) private var theme

    private var api: SloppyAPIClient {
        apiClient ?? SloppyAPIClient(baseURL: settings.baseURL)
    }

    private var canConnect: Bool {
        !inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
    }

    var body: some View {
        content
            .onAppear { refreshNodes() }
    }

    @ViewBuilder
    private var content: some View {
#if os(iOS)
        mobileForm
#else
        desktopContent
#endif
    }

#if os(iOS)
    private var mobileForm: some View {
        Form {
            Section {
                LabeledContent("Invite token") {
                    TextField("slp_mesh_…", text: $inviteToken)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.go)
                        .onSubmit(acceptInvite)
                        .disabled(isConnecting)
                        .accessibilityLabel("Invite token")
                        .accessibilityIdentifier("settings.mesh.invite-token")
                }

                Button(action: acceptInvite) {
                    HStack {
                        Label(isConnecting ? "Connecting…" : "Connect", systemImage: "link")
                        Spacer()
                        if isConnecting { ProgressView() }
                    }
                    .foregroundStyle(canConnect ? Color.accentColor : .secondary)
                }
                .disabled(!canConnect)
                .accessibilityIdentifier("settings.mesh.connect")
            } header: {
                Text("Join a mesh")
            } footer: {
                Text("Connect another machine using an invite beginning with slp_mesh_.")
            }

            Section {
                if isLoading && nodes.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Discovering nodes…")
                            .foregroundStyle(.secondary)
                    }
                } else if nodes.isEmpty {
                    Label("No connected nodes", systemImage: "network")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nodes) { node in
                        mobileNodeRow(node)
                    }
                }
            } header: {
                Text("Connected nodes")
            } footer: {
                Text(nodes.isEmpty ? discoveryHint : "Choose the default node for this client.")
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: hasError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(hasError ? Color.red : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .buttonStyle(.automatic)
        .mobileScreenBackground()
        .mobileRefreshable { await loadNodes() }
        .accessibilityIdentifier("settings.mesh.form")
    }

    private func mobileNodeRow(_ node: MeshNodeRecord) -> some View {
        let selected = node.id == settings.meshTargetNodeId
        return Button {
            settings.meshTargetNodeId = node.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.displayName)
                        .foregroundStyle(.primary)
                    Text(node.status.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let connectionDisplayName = node.connectionDisplayName {
                        Text(connectionDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Default")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Set as the default mesh node")
        .accessibilityIdentifier("settings.mesh.node.\(node.id)")
    }
#endif

    private var desktopContent: some View {
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
                    .appPrimaryButton()
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
#if !os(iOS)
                    Button(action: refreshNodes) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || isConnecting)
                    .accessibilityIdentifier("settings.mesh.refresh")
#endif
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
                        Text(discoveryHint)
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
                    if let connectionDisplayName = node.connectionDisplayName {
                        Label(connectionDisplayName, systemImage: "network")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .help(node.endpoint ?? connectionDisplayName)
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
        Task { await loadNodes() }
    }

    private var discoveryHint: String {
#if os(iOS)
        "Use an invite token above, or pull down to discover nodes."
#else
        "Use an invite token above, or refresh to discover nodes."
#endif
    }

    private func loadNodes() async {
        guard !isLoading else { return }
        isLoading = true
        hasError = false
        if !isConnecting { statusMessage = nil }

        defer { isLoading = false }

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
