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
    case client
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
        case .client: "General"
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
        case .client: "Connection, appearance, accent, and desktop behavior."
        case .mesh: "Mesh invite and target node selection."
        case .providers: "Model providers, API URLs, auth, and defaults."
        case .searchTools: "Web search provider routing and credentials."
        case .channels: "Telegram and Discord gateway settings."
        case .plugins: "Plugin connections and delivery endpoints."
        case .nodeHost: "Remote and local node host configuration."
        case .visor: "Scheduler, runtime maintenance, and merge settings."
        case .acp: "ACP targets and agent communication settings."
        case .proxy: "SOCKS/HTTP proxy credentials and routing."
        case .gitSync: "Repository, schedule, and conflict behavior."
        case .rawConfig: "Inspect and edit raw JSON config."
        case .modelRouting: "Dashboard section not yet backed by app-native models."
        case .sessions: "Dashboard section not yet backed by app-native models."
        case .approvals: "Dashboard section not yet backed by app-native models."
        case .mcp: "Dashboard section not yet backed by app-native models."
        case .browser: "Dashboard section not yet backed by app-native models."
        case .voiceMode: "Dashboard section not yet backed by app-native models."
        case .tui: "Dashboard section not yet backed by app-native models."
        case .ui: "Dashboard section not yet backed by app-native models."
        case .compactor: "Dashboard section not yet backed by app-native models."
        case .connectClient: "Dashboard section not yet backed by app-native models."
        case .updates: "Dashboard section not yet backed by app-native models."
        }
    }

    var searchTerms: [String] {
        switch self {
        case .client:
            ["general", "connection", "appearance", "accent", "desktop", "window"]
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
        case .client, .mesh:
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
    @State private var selectedSection: SettingsScreenSection = .client

    private let settings: ClientSettings
    private let onDismiss: (() -> Void)?

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private let api: SloppyAPIClient

    public init(settings: ClientSettings? = nil, onDismiss: (() -> Void)? = nil) {
        self.settings = settings ?? ClientSettings()
        self.onDismiss = onDismiss
        self.api = SloppyAPIClient(baseURL: (settings ?? ClientSettings()).baseURL)
    }

    public var body: some View {
        Group {
            if idiom == .phone {
                phoneLayout
            } else {
                desktopShell
            }
        }
        .onAppear { loadConfig() }
    }

    private var phoneLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                headerSection
                detailContent(for: selectedSection)
            }
            .padding(.bottom, theme.spacing.xxl)
        }
    }

    private var desktopShell: some View {
        return NavigationSplitView(sidebar: {
            settingsSidebar
                .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search settings...")
                .frame(width: 308)
        }, detail: {
            settingsDetailPane
        })
        .frame(minWidth: 1120, maxWidth: .infinity, minHeight: 760, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    private var settingsSidebar: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            if let onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: sp.s) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: ty.caption))
                        Text("Back to app")
                            .font(.system(size: ty.body))
                    }
                    .foregroundColor(c.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, sp.l)
                .padding(.top, sp.l)
            }

            Text("Settings")
                .font(.system(size: ty.caption, weight: .semibold))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.l)

            ScrollView {
                VStack(alignment: .leading, spacing: sp.l) {
                    ForEach(SettingsScreenSectionGroup.allCases, id: \.self) { group in
                        let groupSections = groupedFilteredSections[group] ?? []
                        if !groupSections.isEmpty {
                            VStack(alignment: .leading, spacing: sp.xs) {
                                Text(group.title)
                                    .font(.system(size: ty.caption))
                                    .foregroundColor(c.textMuted)
                                    .padding(.horizontal, sp.l)
                                    .padding(.bottom, sp.xs)

                                ForEach(groupSections, id: \.self) { section in
                                    SettingsSidebarRowView(
                                        section: section,
                                        isSelected: selectedSection == section,
                                        action: { selectedSection = section }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, sp.l)
            }
        }
    }

    private var settingsDetailPane: some View {
        let sp = theme.spacing

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.xl) {
                headerSection
                detailContent(for: selectedSection)
            }
            .padding(.horizontal, sp.xxl)
            .padding(.vertical, sp.xl)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text(selectedSection.title)
                .font(.system(size: ty.title, weight: .semibold))
                .foregroundColor(c.textPrimary)
            Text(selectedSection.subtitle)
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
            Text(statusText)
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
    }

    @ViewBuilder
    private func detailContent(for section: SettingsScreenSection) -> some View {
        switch selectedSection {
        case .client:
            ClientSettingsSection(settings: settings)
            #if os(macOS)
            windowResizeSection
            #endif
        case .mesh:
            MeshSettingsSection(settings: settings)
        case .providers:
            configBackedSection { config in
                ProvidersSection(config: config, onSave: saveConfig)
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

    #if os(macOS)
    private var windowResizeSection: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text("Window")
                    .font(.system(size: theme.typography.heading, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                Text("This settings window now supports a larger default size and live resize on macOS.")
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(theme.colors.textSecondary)
            }
        }
    }
    #endif

    private func loadConfig() {
        statusText = "Loading..."
        Task { @MainActor in
            do {
                let loaded = try await api.fetchConfig()
                self.config = loaded
                self.statusText = "Config loaded"
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

private struct SettingsSidebarRowView: View {
    let section: SettingsScreenSection
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: iconName)
                    .font(.system(size: theme.typography.caption))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: theme.typography.body))
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? theme.colors.surfaceRaised.opacity(0.28 as CGFloat) : .clear)
            )
            .padding(.horizontal, theme.spacing.m)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch section {
        case .client: "gearshape"
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

private struct UnsupportedSettingsSectionView: View {
    let section: SettingsScreenSection

    @Environment(\.theme) private var theme

    var body: some View {
        SettingsSectionSurface {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                Text(section.title)
                    .font(.system(size: theme.typography.heading, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                Text("This dashboard settings section is now represented in the app shell, but its native editor still needs a dedicated Swift model and API wiring.")
                    .font(.system(size: theme.typography.body))
                    .foregroundColor(theme.colors.textSecondary)
                Text("The current screen preserves the dashboard information architecture so we can add native support here without redesigning the window again.")
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
