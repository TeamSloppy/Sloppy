import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct SettingsScreen: View {
    @State private var config: SloppyConfig?
    @State private var statusText = "Loading config…"
    @State private var availableModels: [ProviderModelOption] = []
    @State private var selected: SettingsSection = .general
    @State private var query = ""
    @State private var showsDetail = false
    @State private var isSaving = false
    @State private var revision = 0
    private let settings: ClientSettings
    private let onDismiss: (() -> Void)?
    private let api: SloppyAPIClient
    @Environment(\.theme) private var theme

    public init(settings: ClientSettings? = nil, onDismiss: (() -> Void)? = nil) {
        let settings = settings ?? ClientSettings()
        self.settings = settings
        self.onDismiss = onDismiss
        api = SloppyAPIClient(baseURL: settings.baseURL)
    }
    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 680 || !showsDetail {
                    sidebar.frame(width: geometry.size.width >= 680 ? 240 : geometry.size.width, height: geometry.size.height)
                }
                if geometry.size.width >= 680 { theme.colors.border.frame(width: 1) }
                if geometry.size.width >= 680 || showsDetail {
                    VStack(alignment: .leading, spacing: 0) {
                        if geometry.size.width < 680 { Button("Back to settings") { showsDetail = false }.padding(16) }
                        detail
                    }.frame(width: geometry.size.width >= 680 ? geometry.size.width - 241 : geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.foregroundColor(theme.colors.textPrimary).background(theme.colors.background)
            .sloppyTextInputStyle(theme.colors)
            .onAppear { loadConfig() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.system(size: 21, weight: .semibold))
                Spacer()
                if let onDismiss { Button("Done", action: onDismiss).font(.system(size: 13)) }
            }.padding(.top, 20)
            TextField("Search settings", text: $query).font(.system(size: 13)).padding(.horizontal, 6).frame(height: 36).background(theme.colors.surfaceRaised).accessibilityIdentifier("settings.search")
            ScrollView(respectsSafeArea: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Client", "Sloppy config", "Advanced"], id: \.self) { group in
                        Text(group).font(.system(size: 11)).foregroundColor(theme.colors.textMuted).padding(.top, 14).padding(.bottom, 4)
                        ForEach(SettingsSection.allCases.filter { $0.group == group && $0.matches(query) }) { section in
                            Button { selected = section; showsDetail = true } label: {
                                Text(section.title).font(.system(size: 13)).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                    .background { RoundedRectangle(cornerRadius: 7).fill(selected == section ? theme.colors.surfaceRaised : .clear) }
                            }.accessibilityIdentifier("settings.section.\(section.rawValue)")
                        }
                    }
                }
            }
        }.padding(.horizontal, 14).background(theme.colors.surface)
    }
    private var detail: some View {
        ScrollView(respectsSafeArea: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text(selected.title).font(.system(size: 28, weight: .semibold))
                Text(selected.subtitle).font(.system(size: 14)).foregroundColor(theme.colors.textSecondary)
                if selected != .general {
                    HStack {
                        Text(statusText).font(.system(size: 12)).foregroundColor(theme.colors.textMuted)
                        Spacer()
                        Button("Reload") { loadConfig() }.disabled(isSaving)
                    }
                }
                if selected == .general { ClientSettingsSection(settings: settings) }
                else if selected == .account { AccountPreferences(service: api.workspace) }
                else if selected == .approvals { ApprovalPreferences(service: api.workspace) }
                else if selected == .proactivity { ProactivityPreferences(api: api) }
                else if selected == .sessions { SessionPreferences(api: api) }
                else if selected == .connectClient { ConnectionPreferences(settings: settings) }
                else if selected == .mesh || selected == .voiceMode { ServiceStatusPreferences(service: api.workspace, isVoice: selected == .voiceMode).id(selected.rawValue) }
                else if let config { section(config).id("\(selected.rawValue):\(revision)").disabled(isSaving) }
                else { Button("Retry loading configuration") { loadConfig() } }
            }.padding(28).frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    @ViewBuilder private func section(_ config: SloppyConfig) -> some View {
        switch selected {
        case .general, .account, .approvals, .proactivity, .sessions, .mesh, .voiceMode, .connectClient: EmptyView()
        case .providers: ProvidersSection(config: config, availableModels: availableModels, onSave: saveConfig)
        case .searchTools: SearchToolsSection(config: config, onSave: saveConfig)
        case .channels: ChannelsSection(config: config, onSave: saveConfig)
        case .plugins: PluginsSection(config: config, onSave: saveConfig)
        case .visor: VisorSection(config: config, onSave: saveConfig)
        case .acp: ACPSection(config: config, onSave: saveConfig)
        case .proxy: ProxySection(config: config, onSave: saveConfig)
        case .gitSync: GitSyncSection(config: config, onSave: saveConfig)
        case .nodes: editor(config, \.nodes)
        case .semanticDecisions: editor(config, \.semanticDecisions)
        case .modelRouting: editor(config, \.modelRouting)
        case .mcp: editor(config, \.mcp)
        case .browser: editor(config, \.browser)
        case .ui: editor(config, \.ui)
        case .tui: editor(config, \.tui)
        case .compactor: editor(config, \.compactor)
        case .memory: editor(config, \.memory)
        case .toolHooks: editor(config, \.toolHooks)
        case .experimental: editor(config, \.experimentalFlags)
        case .raw: RawConfigSection(config: config)
        }
    }
    private func editor<Value: Codable & Sendable>(_ config: SloppyConfig, _ keyPath: WritableKeyPath<SloppyConfig, Value>) -> some View {
        ConfigValueEditor(config[keyPath: keyPath]) { value in
            var updated = config
            updated[keyPath: keyPath] = value
            saveConfig(updated)
        }
    }
    private func loadConfig() {
        guard !isSaving else { return }
        statusText = "Loading…"
        Task { @MainActor in
            do {
                async let models = api.fetchAvailableModels()
                config = try await api.fetchConfig()
                availableModels = (try? await models) ?? []
                revision += 1
                statusText = "Configuration loaded"
            } catch { statusText = error.localizedDescription }
        }
    }
    private func saveConfig(_ updated: SloppyConfig) {
        guard !isSaving else { return }
        isSaving = true
        statusText = "Saving…"
        Task { @MainActor in
            defer { isSaving = false }
            do {
                config = try await api.updateConfig(updated)
                revision += 1
                statusText = "Saved"
            } catch { statusText = error.localizedDescription }
        }
    }
}
