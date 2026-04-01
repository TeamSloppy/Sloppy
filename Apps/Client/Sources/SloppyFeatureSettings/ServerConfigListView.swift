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
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Sloppy Config", accentColor: c.accentCyan)
                .padding(.horizontal, sp.m)

            if idiom == .phone {
                phoneLayout
            } else {
                desktopLayout
            }
        }
    }

    private var phoneLayout: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders

        return NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ConfigSection.allCases, id: \.self) { section in
                    NavigationLink(value: section) {
                        configRow(section)
                    }
                }
            }
            .background(c.surface)
            .border(c.border, lineWidth: bo.thin)
            .padding(.horizontal, sp.m)
            .navigate(for: ConfigSection.self) { section in
                configDetailView(section)
            }
        }
    }

    private var desktopLayout: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ConfigSection.allCases, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        configRow(section)
                    }
                    .background(selectedSection == section ? c.surfaceRaised : Color.clear)
                }
            }
            .frame(width: 200)
            .background(c.surface)
            .border(c.border, lineWidth: bo.thin)

            Color.clear.frame(width: bo.thin).background(c.border)

            if let section = selectedSection {
                ScrollView {
                    configDetailView(section)
                        .padding(sp.m)
                }
            } else {
                VStack {
                    Spacer()
                    Text("SELECT A SECTION")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                    Spacer()
                }
            }
        }
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
        .padding(.horizontal, sp.m)
    }

    private func configRow(_ section: ConfigSection) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack {
            Text(section.title.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(selectedSection == section ? c.textPrimary : c.textSecondary)
            Spacer()
            Text(">")
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
        .background(Color.clear)
        .border(c.border, lineWidth: bo.thin)
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
