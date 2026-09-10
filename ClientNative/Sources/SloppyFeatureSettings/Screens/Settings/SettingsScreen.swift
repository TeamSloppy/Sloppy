import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

enum SettingsScreenSectionGroup: String, CaseIterable, Hashable {
    case client
    case config
    case advanced

    var title: String {
        switch self {
        case .client: "Client"
        case .config: "Config"
        case .advanced: "Advanced"
        }
    }
}

enum SettingsScreenSection: String, CaseIterable, Hashable, Identifiable {
    case account
    case client
    case backend
    case mesh
    case providers
    case searchTools
    case channels
    case plugins
    case nodeHost
    case visor
    case acp
    case proxy
    case gitSync
    case rawConfig
    case modelRouting
    case sessions
    case approvals
    case mcp
    case browser
    case voiceMode
    case tui
    case ui
    case compactor
    case connectClient
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .client: "General"
        case .backend: "Sloppy Backend"
        case .mesh: "Mesh"
        case .providers: "Providers"
        case .searchTools: "Search Tools"
        case .channels: "Channels"
        case .plugins: "Plugins"
        case .nodeHost: "Node Host"
        case .visor: "Visor"
        case .acp: "ACP"
        case .proxy: "Proxy"
        case .gitSync: "Git Sync"
        case .rawConfig: "Config"
        case .modelRouting: "Model routing"
        case .sessions: "Sessions"
        case .approvals: "Approvals"
        case .mcp: "MCP"
        case .browser: "Browser"
        case .voiceMode: "Voice Mode"
        case .tui: "TUI"
        case .ui: "UI"
        case .compactor: "Compactor"
        case .connectClient: "Connect Client"
        case .updates: "Updates"
        }
    }

    var subtitle: String {
        switch self {
        case .account: "Profile, password, recovery codes, application tokens, and sign out."
        case .client: "Connection, appearance, accent, and desktop behavior."
        case .backend: "Install or update the local Sloppy backend from GitHub Releases."
        case .mesh: "Connect your machines and choose where to work."
        case .providers: "Model providers, API URLs, auth, and defaults."
        case .searchTools: "Web search provider routing and credentials."
        case .channels: "Telegram and Discord gateway settings."
        case .plugins: "Plugin connections and delivery endpoints."
        case .nodeHost: "Remote and local node host configuration."
        case .visor: "Scheduler, runtime maintenance, and merge settings."
        case .acp: "ACP targets and agent communication settings."
        case .proxy: "SOCKS/HTTP proxy credentials and routing."
        case .gitSync: "Repository, schedule, and conflict behavior."
        case .rawConfig: "Inspect your server configuration as JSON."
        case .modelRouting: "Aliases for fast, heavy, and specialized models."
        case .sessions: "Manage conversation history and retention."
        case .approvals: "People with access through your connected channels."
        case .mcp: "Servers, tools, resources, and prompts available to agents."
        case .browser: "Browser connections, profiles, and automation."
        case .voiceMode: "Speech, audio, and transcription preferences."
        case .tui: "Your preferred editor for the terminal interface."
        case .ui: "Dashboard access, terminal, and tool execution preferences."
        case .compactor: "Context limits, reduction thresholds, and retries."
        case .connectClient: "Pair another client with your Sloppy server."
        case .updates: "Sloppy versions and updates."
        }
    }

    var searchTerms: [String] {
        switch self {
        case .account:
            ["account", "profile", "name", "login", "password", "recovery", "token", "sign out"]
        case .client:
            ["general", "connection", "appearance", "accent", "desktop", "window"]
        case .backend:
            ["backend", "install", "installation", "release", "update", "github", "local"]
        case .mesh:
            ["mesh", "invite", "node", "sharing", "target"]
        case .providers:
            ["models", "api key", "api url", "openai", "anthropic", "gemini", "ollama", "openrouter"]
        case .searchTools:
            ["search", "brave", "perplexity", "web", "provider"]
        case .channels:
            ["telegram", "discord", "bot token", "guild", "channels"]
        case .plugins:
            ["plugins", "extension", "api url", "delivery"]
        case .nodeHost:
            ["node host", "nodes", "gateway", "host", "token"]
        case .visor:
            ["visor", "scheduler", "worker timeout", "branch timeout", "merge"]
        case .acp:
            ["acp", "targets", "agent communication", "command"]
        case .proxy:
            ["proxy", "socks5", "http", "https", "host", "port"]
        case .gitSync:
            ["git", "sync", "repository", "branch", "schedule"]
        case .rawConfig:
            ["raw", "json", "config", "advanced"]
        case .modelRouting:
            ["routing", "routes", "aliases", "default model"]
        case .sessions:
            ["sessions", "retention", "history", "cleanup"]
        case .approvals:
            ["approvals", "permissions", "pending", "requests"]
        case .mcp:
            ["mcp", "servers", "resources", "prompts", "tools"]
        case .browser:
            ["browser", "chromium", "cdp", "headless", "profile"]
        case .voiceMode:
            ["voice", "speech", "audio", "tts", "transcription"]
        case .tui:
            ["tui", "terminal", "cli", "editor"]
        case .ui:
            ["ui", "dashboard", "auth", "token", "terminal"]
        case .compactor:
            ["compactor", "context", "compact", "tokens", "reduction"]
        case .connectClient:
            ["client", "qr", "mobile", "connect"]
        case .updates:
            ["updates", "version", "release", "upgrade"]
        }
    }

    var group: SettingsScreenSectionGroup {
        switch self {
        case .account, .client, .backend, .mesh:
            .client
        case .providers, .searchTools, .channels, .plugins, .nodeHost, .visor, .acp, .proxy, .gitSync, .rawConfig:
            .config
        case .modelRouting, .sessions, .approvals, .mcp, .browser, .voiceMode, .tui, .ui, .compactor, .connectClient, .updates:
            .advanced
        }
    }
}

public struct SettingsScreen: View {
    @State private var config: SloppyConfig? = nil
    @State private var statusText: String = "Loading config..."
    @State private var searchQuery: String = ""
    @State private var selectedSection: SettingsScreenSection?
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    private let settings: ClientSettings
    private let initialSection: SettingsScreenSection
    private let onDismiss: (() -> Void)?
    private let onChangeServer: (@MainActor () -> Void)?
    private let onLogout: (@MainActor () -> Void)?

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private let api: SloppyAPIClient

    public init(
        settings: ClientSettings? = nil,
        initialDestination: ClientSettingsDestination = .general,
        onDismiss: (() -> Void)? = nil,
        onChangeServer: (@MainActor () -> Void)? = nil,
        onLogout: (@MainActor () -> Void)? = nil
    ) {
        self.settings = settings ?? ClientSettings()
        self.onDismiss = onDismiss
        self.onChangeServer = onChangeServer
        self.onLogout = onLogout
        self.api = SloppyAPIClient(baseURL: (settings ?? ClientSettings()).baseURL)
        let initialSection: SettingsScreenSection
        switch initialDestination {
        case .account:
            initialSection = .account
        case .general:
            initialSection = .client
        case .providers:
            initialSection = .providers
        }
        self.initialSection = initialSection
        self._selectedSection = State(initialValue: nil)
    }

    public var body: some View {
        settingsShell
        .onAppear {
            if idiom != .phone, selectedSection == nil {
                selectedSection = initialSection
                return
            }
            if displayedSection != .account {
                loadConfig()
            }
        }
        .onChange(of: selectedSection) { _, section in
            if section != nil, section != .account, config == nil {
                loadConfig()
            }
        }
    }

    private var settingsShell: some View {
        return NavigationSplitView(preferredCompactColumn: $preferredCompactColumn, sidebar: {
            settingsSidebar
                #if !os(macOS)
                .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search settings...")
                #endif
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        }, detail: {
            settingsDetailPane
        })
        #if os(macOS)
        .frame(minWidth: 1120, maxWidth: .infinity, minHeight: 760, maxHeight: .infinity)
        #endif
        .background(theme.colors.background)
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            SettingsSearchField(text: $searchQuery)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            #endif
            settingsSidebarList
        }
    }

    private var settingsSidebarList: some View {
        List(selection: $selectedSection) {
            if let onDismiss, idiom != .phone {
                Section {
                    Button(action: onDismiss) {
                        Label("Back to app", systemImage: "arrow.left")
                    }
                    .buttonStyle(.plain)
                }
            }

            if filteredSections.isEmpty {
                Text("No matching settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }

            ForEach(SettingsScreenSectionGroup.allCases, id: \.self) { group in
                let groupSections = groupedFilteredSections[group] ?? []
                if !groupSections.isEmpty {
                    Section(group.title) {
                        ForEach(groupSections, id: \.self) { section in
                            Label(section.title, systemImage: section.iconName)
                                .tag(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .toolbar {
            #if os(iOS)
            if let onDismiss, idiom == .phone {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to app")
                }
            }
            #endif
        }
    }

    private var settingsDetailPane: some View {
        let sp = theme.spacing

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.xl) {
                headerSection
                detailContent(for: displayedSection)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(idiom == .phone ? sp.m : sp.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .navigationTitle(displayedSection.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var headerSection: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text(displayedSection.title)
                .font(.system(size: ty.title, weight: .semibold))
                .foregroundColor(c.textPrimary)
            Text(displayedSection.subtitle)
                .font(.system(size: ty.body))
                .foregroundColor(c.textSecondary)
            if displayedSection != .backend, displayedSection != .account,
               displayedSection != .client, displayedSection != .mesh, !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
            }
        }
    }

    @ViewBuilder
    private func detailContent(for section: SettingsScreenSection) -> some View {
        switch section {
        case .account:
            AccountSettingsSection(apiClient: api, onLogout: onLogout ?? {})
        case .client:
            ClientSettingsSection(
                settings: settings,
                onChangeServer: onChangeServer ?? {}
            )
        case .backend:
            #if os(macOS)
            BackendSettingsSection()
            #else
            UnsupportedSettingsSectionView(section: section)
            #endif
        case .mesh:
            MeshSettingsSection(settings: settings)
        case .providers:
            configBackedSection { config in
                ProvidersSection(config: config, apiClient: api, onSave: saveConfig)
            }
        case .searchTools:
            configBackedSection { config in
                SearchToolsSection(config: config, onSave: saveConfig)
            }
        case .channels:
            configBackedSection { config in
                ChannelsSection(config: config, onSave: saveConfig)
            }
        case .plugins:
            configBackedSection { config in
                PluginsSection(config: config, onSave: saveConfig)
            }
        case .nodeHost:
            configBackedSection { config in
                NodeHostSection(config: config, onSave: saveConfig)
            }
        case .visor:
            configBackedSection { config in
                VisorSection(config: config, onSave: saveConfig)
            }
        case .acp:
            configBackedSection { config in
                ACPSection(config: config, onSave: saveConfig)
            }
        case .proxy:
            configBackedSection { config in
                ProxySection(config: config, onSave: saveConfig)
            }
        case .gitSync:
            configBackedSection { config in
                GitSyncSection(config: config, onSave: saveConfig)
            }
        case .rawConfig:
            configBackedSection { config in
                RawConfigSection(config: config)
            }
        case .modelRouting:
            configBackedSection { config in
                ModelRoutingSection(config: config, onSave: saveConfig)
            }
        case .approvals:
            ApprovalsSection(apiClient: api)
        case .mcp:
            configBackedSection { config in
                MCPSection(config: config, onSave: saveConfig)
            }
        case .browser:
            configBackedSection { config in
                BrowserSection(config: config, onSave: saveConfig)
            }
        case .tui:
            configBackedSection { config in
                TUISection(config: config, onSave: saveConfig)
            }
        case .ui:
            configBackedSection { config in
                UISection(config: config, onSave: saveConfig)
            }
        case .compactor:
            configBackedSection { config in
                CompactorSection(config: config, onSave: saveConfig)
            }
        case .connectClient:
            configBackedSection { config in
                ConnectClientSection(config: config, settings: settings)
            }
        case .sessions, .voiceMode, .updates:
            UnsupportedSettingsSectionView(section: section)
        }
    }

    private var displayedSection: SettingsScreenSection {
        selectedSection ?? initialSection
    }

    @ViewBuilder
    private func configBackedSection<Content: View>(_ builder: (SloppyConfig) -> Content) -> some View {
        if let config {
            builder(config)
        } else {
            loadingOrErrorView
        }
    }

    private var groupedFilteredSections: [SettingsScreenSectionGroup: [SettingsScreenSection]] {
        Dictionary(
            grouping: filteredSections,
            by: \.group
        )
    }

    private var filteredSections: [SettingsScreenSection] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SettingsScreenSection.allCases
        }

        let lowered = query.lowercased()
        return SettingsScreenSection.allCases.filter { section in
            section.title.lowercased().contains(lowered)
            || section.subtitle.lowercased().contains(lowered)
            || section.searchTerms.contains(where: { $0.lowercased().contains(lowered) })
        }
    }

    private var loadingOrErrorView: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return SettingsSectionSurface {
            VStack(alignment: .leading, spacing: sp.m) {
                Text(statusText)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textMuted)
                Button("Retry") { loadConfig() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accent)
            }
        }
    }

    private func loadConfig() {
        statusText = "Loading..."
        Task { @MainActor in
            do {
                let loaded = try await api.fetchConfig()
                self.config = loaded
                self.statusText = ""
            } catch {
                self.statusText = "Failed to load config"
            }
        }
    }

    private func saveConfig(_ updated: SloppyConfig) {
        statusText = "Saving..."
        Task { @MainActor in
            do {
                let saved = try await api.updateConfig(updated)
                self.config = saved
                self.statusText = "Saved"
            } catch {
                self.statusText = "Failed to save"
            }
        }
    }
}

private extension SettingsScreenSection {
    var iconName: String {
        switch self {
        case .account: "person.crop.circle"
        case .client: "gearshape"
        case .backend: "shippingbox.and.arrow.backward"
        case .mesh: "point.3.connected.trianglepath.dotted"
        case .providers: "sparkles"
        case .searchTools: "magnifyingglass"
        case .channels: "message"
        case .plugins: "puzzlepiece.extension"
        case .nodeHost: "network"
        case .visor: "eye"
        case .acp: "cpu"
        case .proxy: "lock.shield"
        case .gitSync: "arrow.triangle.2.circlepath"
        case .rawConfig: "doc.text"
        case .modelRouting: "point.topleft.down.curvedto.point.bottomright.up"
        case .sessions: "clock.arrow.circlepath"
        case .approvals: "checkmark.shield"
        case .mcp: "point.3.filled.connected.trianglepath.dotted"
        case .browser: "globe"
        case .voiceMode: "mic"
        case .tui: "terminal"
        case .ui: "paintpalette"
        case .compactor: "rectangle.compress.vertical"
        case .connectClient: "qrcode"
        case .updates: "square.and.arrow.down"
        }
    }
}

struct UnsupportedSettingsSectionView: View {
    let section: SettingsScreenSection

    var body: some View {
        SettingsSectionSurface {
            ContentUnavailableView(
                "Available in the dashboard",
                systemImage: section.iconName,
                description: Text("Manage these preferences in your Sloppy dashboard. This section is not available in the native client yet.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }
}

#Preview {
    SettingsScreen()
}
