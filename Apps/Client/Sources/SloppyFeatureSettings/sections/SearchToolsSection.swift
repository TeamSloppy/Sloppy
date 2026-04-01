import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct SearchToolsSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var activeProvider: String
    @State private var braveApiKey: String
    @State private var perplexityApiKey: String
    @Environment(\.theme) private var theme

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._activeProvider = State(initialValue: config.searchTools.activeProvider)
        self._braveApiKey = State(initialValue: config.searchTools.providers.brave.apiKey)
        self._perplexityApiKey = State(initialValue: config.searchTools.providers.perplexity.apiKey)
    }

    private var hasChanges: Bool {
        activeProvider != config.searchTools.activeProvider ||
        braveApiKey != config.searchTools.providers.brave.apiKey ||
        perplexityApiKey != config.searchTools.providers.perplexity.apiKey
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Search Tools", accentColor: c.accentCyan)

            SettingsSectionCard("Active Provider") {
                HStack(spacing: sp.s) {
                    ForEach(["perplexity", "brave"], id: \.self) { provider in
                        Button(provider.capitalized) {
                            activeProvider = provider
                        }
                        .font(.system(size: ty.caption))
                        .foregroundColor(activeProvider == provider ? c.textPrimary : c.textMuted)
                        .padding(.vertical, sp.xs)
                        .padding(.horizontal, sp.s)
                        .background(activeProvider == provider ? c.surfaceRaised : Color.clear)
                        .border(activeProvider == provider ? c.borderBold : c.border, lineWidth: bo.thin)
                    }
                    Spacer()
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
            }

            SettingsSectionCard("Perplexity") {
                SettingsFieldRow("API Key", text: $perplexityApiKey, isSecure: true)
            }

            SettingsSectionCard("Brave") {
                SettingsFieldRow("API Key", text: $braveApiKey, isSecure: true)
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { reset() }
            )
        }
    }

    private func reset() {
        activeProvider = config.searchTools.activeProvider
        braveApiKey = config.searchTools.providers.brave.apiKey
        perplexityApiKey = config.searchTools.providers.perplexity.apiKey
    }

    private func save() {
        var updated = config
        updated.searchTools.activeProvider = activeProvider
        updated.searchTools.providers.brave.apiKey = braveApiKey
        updated.searchTools.providers.perplexity.apiKey = perplexityApiKey
        onSave(updated)
    }
}
