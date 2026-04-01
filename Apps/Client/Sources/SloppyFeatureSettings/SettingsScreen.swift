import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct SettingsScreen: View {
    @State private var config: SloppyConfig? = nil
    @State private var statusText: String = "Loading config..."
    @State private var settings = ClientSettings()
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    private let api = SloppyAPIClient()

    public init() {}

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.xl) {
                headerSection

                ClientSettingsSection(settings: settings)

                if let config {
                    ServerConfigListView(config: config, onSave: saveConfig)
                } else {
                    loadingOrErrorView
                }
            }
            .padding(.bottom, sp.xxl)
        }
        .background(c.background)
        .onAppear { loadConfig() }
    }

    private var headerSection: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text("SETTINGS")
                .font(.system(size: ty.hero))
                .foregroundColor(c.textPrimary)
            Color.clear
                .frame(width: 60, height: bo.thick)
                .background(c.accent)
            Text(statusText.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
        .padding(sp.l)
    }

    private var loadingOrErrorView: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Sloppy Config", accentColor: c.accentCyan)
                .padding(.horizontal, sp.m)
            Text(statusText)
                .font(.system(size: ty.body))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.m)
            Button("RETRY") { loadConfig() }
                .font(.system(size: ty.caption))
                .foregroundColor(c.accent)
                .padding(.horizontal, sp.m)
        }
    }

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
