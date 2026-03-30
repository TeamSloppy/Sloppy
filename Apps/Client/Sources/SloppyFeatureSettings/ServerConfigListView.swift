import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum ConfigSection: String, CaseIterable, Hashable {
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

    var title: String {
        switch self {
        case .providers: "Providers"
        case .searchTools: "Search Tools"
        case .channels: "Channels"
        case .plugins: "Plugins"
        case .nodeHost: "Node Host"
        case .visor: "Visor"
        case .acp: "ACP"
        case .proxy: "Proxy"
        case .gitSync: "Git Sync"
        case .rawConfig: "Raw Config"
        }
    }
}

struct ServerConfigListView: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var selectedSection: ConfigSection? = nil
    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Sloppy Config", accentColor: Theme.accentCyan)
                .padding(.horizontal, Theme.spacingM)

            if idiom == .phone {
                phoneLayout
            } else {
                desktopLayout
            }
        }
    }

    private var phoneLayout: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ConfigSection.allCases, id: \.self) { section in
                    NavigationLink(value: section) {
                        configRow(section)
                    }
                }
            }
            .background(Theme.surface)
            .border(Theme.border, lineWidth: Theme.borderThin)
            .padding(.horizontal, Theme.spacingM)
            .navigate(for: ConfigSection.self) { section in
                configDetailView(section)
            }
        }
    }

    private var desktopLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ConfigSection.allCases, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        configRow(section)
                    }
                    .background(selectedSection == section ? Theme.surfaceRaised : Color.clear)
                }
            }
            .frame(width: 200)
            .background(Theme.surface)
            .border(Theme.border, lineWidth: Theme.borderThin)

            Color.clear.frame(width: Theme.borderThin).background(Theme.border)

            if let section = selectedSection {
                ScrollView {
                    configDetailView(section)
                        .padding(Theme.spacingM)
                }
            } else {
                VStack {
                    Spacer()
                    Text("SELECT A SECTION")
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
            }
        }
        .background(Theme.surface)
        .border(Theme.border, lineWidth: Theme.borderThin)
        .padding(.horizontal, Theme.spacingM)
    }

    private func configRow(_ section: ConfigSection) -> some View {
        HStack {
            Text(section.title.uppercased())
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(selectedSection == section ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
            Text(">")
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(Color.clear)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }

    @ViewBuilder
    private func configDetailView(_ section: ConfigSection) -> some View {
        switch section {
        case .providers:
            ProvidersSection(config: config, onSave: onSave)
        case .searchTools:
            SearchToolsSection(config: config, onSave: onSave)
        case .channels:
            ChannelsSection(config: config, onSave: onSave)
        case .plugins:
            PluginsSection(config: config, onSave: onSave)
        case .nodeHost:
            NodeHostSection(config: config, onSave: onSave)
        case .visor:
            VisorSection(config: config, onSave: onSave)
        case .acp:
            ACPSection(config: config, onSave: onSave)
        case .proxy:
            ProxySection(config: config, onSave: onSave)
        case .gitSync:
            GitSyncSection(config: config, onSave: onSave)
        case .rawConfig:
            RawConfigSection(config: config)
        }
    }
}
