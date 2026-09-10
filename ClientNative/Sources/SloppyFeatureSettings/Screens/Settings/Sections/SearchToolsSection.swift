import Foundation
import SwiftUI
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
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Active Provider") {
                Picker("Active provider", selection: $activeProvider) {
                    Text("Perplexity").tag("perplexity")
                    Text("Brave").tag("brave")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(16)
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
