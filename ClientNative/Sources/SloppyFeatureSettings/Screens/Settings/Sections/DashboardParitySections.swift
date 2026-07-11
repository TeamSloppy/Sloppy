import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins
import SloppyClientCore
import SloppyClientUI

#if os(macOS)
import AppKit
#endif

struct ModelRoutingSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var aliases: [(String, String)] = []
    @State private var statusText = ""

    var body: some View {
        SettingsSectionCard("Model Routing") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(aliases.enumerated()), id: \.offset) { index, pair in
                    aliasRow(index: index, key: pair.0, value: pair.1)
                    if index < aliases.count - 1 {
                        SettingsDivider()
                    }
                }

                HStack {
                    Button("Add Alias") {
                        aliases.append(("", ""))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Spacer()
                    Button("Save") { save() }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            aliases = config.modelRouting.keys.sorted().map { ($0, config.modelRouting[$0] ?? "") }
            if aliases.isEmpty {
                aliases = [("fast", ""), ("heavy", "")]
            }
        }
    }

    private func aliasRow(index: Int, key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsFieldRow("Alias", text: Binding(
                get: { aliases[index].0 },
                set: { aliases[index].0 = $0 }
            ))
            SettingsFieldRow("Model", hint: "Configured provider model ID or alias target.", text: Binding(
                get: { aliases[index].1 },
                set: { aliases[index].1 = $0 }
            ))
            HStack {
                Spacer()
                Button("Remove") {
                    aliases.remove(at: index)
                    if aliases.isEmpty {
                        aliases.append(("", ""))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func save() {
        var updated = config
        updated.modelRouting = Dictionary(
            uniqueKeysWithValues: aliases.compactMap { key, value in
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedKey.isEmpty, !trimmedValue.isEmpty else { return nil }
                return (trimmedKey, trimmedValue)
            }
        )
        onSave(updated)
        statusText = "Saved"
    }
}

struct BrowserSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: SloppyConfig.Browser

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _draft = State(initialValue: config.browser)
    }

    var body: some View {
        SettingsSectionCard("Browser") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(label: "Enable Browser Automation", value: draft.enabled) { draft.enabled.toggle() }
                SettingsDivider()
                SettingsFieldRow("Executable Path", hint: "Optional when CDP endpoint is set.", text: binding(\.executablePath))
                SettingsDivider()
                SettingsFieldRow("CDP Endpoint", hint: "HTTP or WebSocket DevTools endpoint.", text: binding(\.cdpEndpoint))
                SettingsDivider()
                SettingsFieldRow("Profile Name", text: binding(\.profileName))
                SettingsDivider()
                SettingsFieldRow("Profile Path", hint: "Optional user-data-dir override.", text: binding(\.profilePath))
                SettingsDivider()
                SettingsFieldRow("Startup Timeout (ms)", text: Binding(
                    get: { String(draft.startupTimeoutMs) },
                    set: { draft.startupTimeoutMs = Int($0) ?? 10_000 }
                ))
                SettingsDivider()
                SettingsToggleRow(label: "Headless", value: draft.headless) { draft.headless.toggle() }
                SettingsDivider()
                SettingsFieldRow("Extra Arguments", hint: "One Chromium argument per line.", text: Binding(
                    get: { draft.additionalArguments.joined(separator: "\n") },
                    set: { draft.additionalArguments = $0.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                saveBar
            }
        }
    }

    private var saveBar: some View {
        HStack {
            Spacer()
            Button("Save") {
                var updated = config
                updated.browser = draft
                onSave(updated)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SloppyConfig.Browser, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }
}

struct MCPSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var servers: [SloppyConfig.MCPServer]
    @State private var selectedIndex: Int = 0

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _servers = State(initialValue: config.mcp.servers.isEmpty ? [SloppyConfig.MCPServer()] : config.mcp.servers)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsSectionSurface {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(servers.enumerated()), id: \.offset) { index, server in
                        Button(server.id) {
                            selectedIndex = index
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedIndex == index ? .primary : .secondary)
                    }
                    Button("Add Server") {
                        servers.append(SloppyConfig.MCPServer(id: "mcp-server-\(servers.count + 1)"))
                        selectedIndex = servers.count - 1
                    }
                    .padding(.top, 8)
                }
            }
            .frame(width: 220)

            SettingsSectionCard("MCP") {
                if servers.indices.contains(selectedIndex) {
                    editor(for: selectedIndex)
                }
            }
        }
    }

    private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsFieldRow("Server ID", text: binding(index, \.id))
            SettingsDivider()
            SettingsFieldRow("Transport", hint: "stdio or http", text: binding(index, \.transport))
            SettingsDivider()
            if servers[index].transport == "http" {
                SettingsFieldRow("Endpoint", text: binding(index, \.endpoint))
                SettingsDivider()
                SettingsFieldRow("Headers", hint: "One header per line: Name: value", text: Binding(
                    get: { servers[index].headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n") },
                    set: { value in
                        let headers = value.split(separator: "\n").reduce(into: [String: String]()) { partial, line in
                            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                            if parts.count == 2 {
                                partial[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                        servers[index].headers = headers
                    }
                ))
            } else {
                SettingsFieldRow("Command", text: binding(index, \.command))
                SettingsDivider()
                SettingsFieldRow("Working Directory", text: binding(index, \.cwd))
                SettingsDivider()
                SettingsFieldRow("Arguments", hint: "One argument per line", text: Binding(
                    get: { servers[index].arguments.joined(separator: "\n") },
                    set: { servers[index].arguments = $0.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty } }
                ))
            }
            SettingsDivider()
            SettingsFieldRow("Timeout (ms)", text: Binding(
                get: { String(servers[index].timeoutMs) },
                set: { servers[index].timeoutMs = Int($0) ?? 15_000 }
            ))
            SettingsDivider()
            SettingsFieldRow("Tool Prefix", text: binding(index, \.toolPrefix))
            SettingsDivider()
            SettingsToggleRow(label: "Enabled", value: servers[index].enabled) { servers[index].enabled.toggle() }
            SettingsDivider()
            SettingsToggleRow(label: "Expose Tools", value: servers[index].exposeTools) { servers[index].exposeTools.toggle() }
            SettingsDivider()
            SettingsToggleRow(label: "Expose Resources", value: servers[index].exposeResources) { servers[index].exposeResources.toggle() }
            SettingsDivider()
            SettingsToggleRow(label: "Expose Prompts", value: servers[index].exposePrompts) { servers[index].exposePrompts.toggle() }
            HStack {
                Button("Delete") {
                    servers.remove(at: index)
                    if servers.isEmpty {
                        servers = [SloppyConfig.MCPServer()]
                    }
                    selectedIndex = min(selectedIndex, servers.count - 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Spacer()
                Button("Save") {
                    var updated = config
                    updated.mcp = SloppyConfig.MCP(servers: servers)
                    onSave(updated)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func binding(_ index: Int, _ keyPath: WritableKeyPath<SloppyConfig.MCPServer, String>) -> Binding<String> {
        Binding(
            get: { servers[index][keyPath: keyPath] },
            set: { servers[index][keyPath: keyPath] = $0 }
        )
    }
}

struct UISection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: SloppyConfig.UI
    @State private var preTools: SloppyConfig.ToolHooks.PreTools
    @State private var toolBudgetExhausted: Int

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _draft = State(initialValue: config.ui)
        _preTools = State(initialValue: config.toolHooks.preTools)
        _toolBudgetExhausted = State(initialValue: config.toolBudgetExhausted)
    }

    var body: some View {
        SettingsSectionCard("UI") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(label: "Dashboard Auth", value: draft.dashboardAuth.enabled) { draft.dashboardAuth.enabled.toggle() }
                SettingsDivider()
                SettingsFieldRow("Dashboard Token", text: Binding(
                    get: { draft.dashboardAuth.token },
                    set: { draft.dashboardAuth.token = $0 }
                ), isSecure: true)
                SettingsDivider()
                SettingsToggleRow(label: "Dashboard Terminal", value: draft.dashboardTerminal.enabled) { draft.dashboardTerminal.enabled.toggle() }
                SettingsDivider()
                SettingsToggleRow(label: "Terminal Local Only", value: draft.dashboardTerminal.localOnly) { draft.dashboardTerminal.localOnly.toggle() }
                SettingsDivider()
                SettingsToggleRow(label: "Pre-tools Hook", value: preTools.enabled) { preTools.enabled.toggle() }
                SettingsDivider()
                SettingsFieldRow("Pre-tools Command", text: Binding(get: { preTools.command }, set: { preTools.command = $0 }))
                SettingsDivider()
                SettingsFieldRow("Pre-tools Arguments", hint: "One argument per line", text: Binding(
                    get: { preTools.arguments.joined(separator: "\n") },
                    set: { preTools.arguments = $0.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
                ))
                SettingsDivider()
                SettingsFieldRow("Pre-tools Timeout (ms)", text: Binding(
                    get: { String(preTools.timeoutMs) },
                    set: { preTools.timeoutMs = Int($0) ?? 2_000 }
                ))
                SettingsDivider()
                SettingsFieldRow("Pre-tools Max Output Bytes", text: Binding(
                    get: { String(preTools.maxOutputBytes) },
                    set: { preTools.maxOutputBytes = Int($0) ?? 65_536 }
                ))
                SettingsDivider()
                SettingsFieldRow("Failure Policy", hint: "block or allow", text: Binding(
                    get: { preTools.failurePolicy },
                    set: { preTools.failurePolicy = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("Tool Budget Exhausted (s)", text: Binding(
                    get: { String(toolBudgetExhausted) },
                    set: { toolBudgetExhausted = Int($0) ?? 60 }
                ))
                HStack {
                    Spacer()
                    Button("Save") {
                        var updated = config
                        updated.ui = draft
                        updated.toolHooks = SloppyConfig.ToolHooks(preTools: preTools)
                        updated.toolBudgetExhausted = toolBudgetExhausted
                        onSave(updated)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct TUISection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var defaultEditor: String

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _defaultEditor = State(initialValue: config.tui.defaultEditor)
    }

    var body: some View {
        SettingsSectionCard("TUI") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldRow("Default Editor", hint: "Examples: zed, code, vim", text: $defaultEditor)
                HStack {
                    Spacer()
                    Button("Save") {
                        var updated = config
                        updated.tui.defaultEditor = defaultEditor
                        onSave(updated)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct CompactorSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: SloppyConfig.Compactor

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _draft = State(initialValue: config.compactor)
    }

    var body: some View {
        SettingsSectionCard("Compactor") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(label: "Enabled", value: draft.enabled) { draft.enabled.toggle() }
                SettingsDivider()
                SettingsFieldRow("Context Window Tokens", text: Binding(
                    get: { String(draft.contextWindowTokens) },
                    set: { draft.contextWindowTokens = Int($0) ?? 32_000 }
                ))
                ForEach(Array(draft.levels.enumerated()), id: \.offset) { index, level in
                    SettingsDivider()
                    SettingsFieldRow("\(level.level.capitalized) Trigger %", text: Binding(
                        get: { String(Int(level.utilizationThreshold * 100)) },
                        set: { draft.levels[index].utilizationThreshold = Double(Int($0) ?? 80) / 100.0 }
                    ))
                    SettingsDivider()
                    SettingsFieldRow("\(level.level.capitalized) Reduction %", text: Binding(
                        get: { String(level.targetReductionPercent) },
                        set: { draft.levels[index].targetReductionPercent = Int($0) ?? 50 }
                    ))
                }
                SettingsDivider()
                SettingsFieldRow("Retry Max Attempts", text: Binding(
                    get: { String(draft.retry.maxAttempts) },
                    set: { draft.retry.maxAttempts = Int($0) ?? 3 }
                ))
                SettingsDivider()
                SettingsFieldRow("Retry Initial Backoff (ms)", text: Binding(
                    get: { String(draft.retry.initialBackoffMs) },
                    set: { draft.retry.initialBackoffMs = Int($0) ?? 250 }
                ))
                HStack {
                    Spacer()
                    Button("Save") {
                        var updated = config
                        updated.compactor = draft
                        onSave(updated)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct ConnectClientSection: View {
    let config: SloppyConfig
    let settings: ClientSettings

    @State private var customHost = ""
    @State private var copied = false

    @Environment(\.theme) private var theme

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        let host = customHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? settings.serverHost : customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = config.listen.port
        let deepLink = "sloppy://connect?host=\(host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host)&port=\(port)&label=\("Sloppy @ \(host)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        return SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                Text("Connect Client")
                    .font(.system(size: theme.typography.heading, weight: .semibold))
                if let qr = qrImage(for: deepLink) {
                    Image(decorative: qr, scale: 1.0)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(12)
                        .background(Color.white)
                }
                SettingsFieldRow("Server Host", hint: "Leave blank to use the current app server host.", text: $customHost)
                SettingsFieldRow("Deep Link", hint: "Scan or copy this URL into another client.", text: .constant(deepLink))
                HStack {
                    Button(copied ? "Copied" : "Copy Link") {
                        #if os(macOS)
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(deepLink, forType: .string)
                        #endif
                        copied = true
                    }
                    Spacer()
                }
            }
        }
    }

    private func qrImage(for string: String) -> CGImage? {
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }
        return context.createCGImage(output, from: output.extent)
    }
}

struct ApprovalsSection: View {
    let apiClient: SloppyAPIClient

    @State private var users: [AccessUser] = []
    @State private var isLoading = false
    @State private var query = ""

    var body: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Channel Access Users")
                        .font(.headline)
                    Spacer()
                    Button(isLoading ? "Loading…" : "Refresh") {
                        load()
                    }
                }
                TextField("Search by name or ID…", text: $query)
                    .textFieldStyle(.roundedBorder)

                if filteredUsers.isEmpty && !isLoading {
                    Text("No access users yet. Approve pending requests from the Channels section.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredUsers) { user in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                Text("\(user.platform) • \(user.platformUserId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(user.status)
                                .font(.caption)
                            Button("Remove") {
                                remove(user)
                            }
                        }
                    }
                }
            }
        }
        .task {
            load()
        }
    }

    private var filteredUsers: [AccessUser] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return users }
        return users.filter {
            $0.displayName.lowercased().contains(lowered)
            || $0.platformUserId.lowercased().contains(lowered)
            || $0.platform.lowercased().contains(lowered)
        }
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            users = (try? await apiClient.fetchAccessUsers()) ?? []
        }
    }

    private func remove(_ user: AccessUser) {
        Task { @MainActor in
            try? await apiClient.deleteAccessUser(user.id)
            users.removeAll { $0.id == user.id }
        }
    }
}
