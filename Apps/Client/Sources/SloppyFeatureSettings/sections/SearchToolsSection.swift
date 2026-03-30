import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct SearchToolsSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var activeProvider: String
    @State private var braveApiKey: String
    @State private var perplexityApiKey: String

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
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Search Tools", accentColor: Theme.accentCyan)

            SettingsSectionCard("Active Provider") {
                HStack(spacing: Theme.spacingS) {
                    ForEach(["perplexity", "brave"], id: \.self) { provider in
                        Button(provider.capitalized) {
                            activeProvider = provider
                        }
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(activeProvider == provider ? Theme.textPrimary : Theme.textMuted)
                        .padding(.vertical, Theme.spacingXS)
                        .padding(.horizontal, Theme.spacingS)
                        .background(activeProvider == provider ? Theme.surfaceRaised : Color.clear)
                        .border(activeProvider == provider ? Theme.borderBold : Theme.border, lineWidth: Theme.borderThin)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingS)
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
