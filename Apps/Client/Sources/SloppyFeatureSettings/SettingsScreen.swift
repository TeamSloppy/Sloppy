import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct SettingsScreen: View {
    @State private var config: SloppyConfig? = nil
    @State private var statusText: String = "Loading config..."
    @State private var settings = ClientSettings()
    @Environment(\.userInterfaceIdiom) private var idiom

    private let api = SloppyAPIClient()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                headerSection

                ClientSettingsSection(settings: settings)

                if let config {
                    ServerConfigListView(config: config, onSave: saveConfig)
                } else {
                    loadingOrErrorView
                }
            }
            .padding(.bottom, Theme.spacingXXL)
        }
        .background(Theme.bg)
        .onAppear { loadConfig() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Text("SETTINGS")
                .font(.system(size: Theme.fontHero))
                .foregroundColor(Theme.textPrimary)
            Color.clear
                .frame(width: 60, height: Theme.borderThick)
                .background(Theme.accent)
            Text(statusText.uppercased())
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textMuted)
        }
        .padding(Theme.spacingL)
    }

    private var loadingOrErrorView: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Sloppy Config", accentColor: Theme.accentCyan)
                .padding(.horizontal, Theme.spacingM)
            Text(statusText)
                .font(.system(size: Theme.fontBody))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, Theme.spacingM)
            Button("RETRY") { loadConfig() }
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.accent)
                .padding(.horizontal, Theme.spacingM)
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
