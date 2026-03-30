import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct PluginsSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: [SloppyConfig.PluginConfig]
    @State private var selectedIndex: Int = 0

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._draft = State(initialValue: config.plugins)
    }

    private var hasChanges: Bool {
        guard draft.count == config.plugins.count else { return true }
        for (index, plugin) in draft.enumerated() {
            let original = config.plugins[index]
            if plugin.title != original.title || plugin.apiKey != original.apiKey || plugin.apiUrl != original.apiUrl || plugin.plugin != original.plugin {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Plugins", accentColor: Theme.accentCyan)

            if draft.isEmpty {
                Text("No plugins configured.")
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.textMuted)
            } else {
                pluginList
                if selectedIndex < draft.count {
                    pluginEditor(index: selectedIndex)
                }
            }

            HStack(spacing: Theme.spacingS) {
                Button("+ ADD") { addPlugin() }
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.accent)
                Spacer()
                if selectedIndex < draft.count && !draft.isEmpty {
                    Button("REMOVE") { removeSelected() }
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.statusBlocked)
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { draft = config.plugins }
            )
        }
    }

    private var pluginList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.enumerated()), id: \.offset) { index, plugin in
                Button(action: { selectedIndex = index }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.title)
                                .font(.system(size: Theme.fontBody))
                                .foregroundColor(index == selectedIndex ? Theme.textPrimary : Theme.textSecondary)
                            Text(plugin.plugin)
                                .font(.system(size: Theme.fontMicro))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)
                    .background(index == selectedIndex ? Theme.surfaceRaised : Color.clear)
                    .border(Theme.border, lineWidth: Theme.borderThin)
                }
            }
        }
        .background(Theme.surface)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }

    private func pluginEditor(index: Int) -> some View {
        SettingsSectionCard("Edit Plugin") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldRow("Title", text: Binding(
                    get: { draft[index].title },
                    set: { draft[index].title = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("Plugin ID", hint: "Plugin identifier string", text: Binding(
                    get: { draft[index].plugin },
                    set: { draft[index].plugin = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("API URL", text: Binding(
                    get: { draft[index].apiUrl },
                    set: { draft[index].apiUrl = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("API Key", text: Binding(
                    get: { draft[index].apiKey },
                    set: { draft[index].apiKey = $0 }
                ), isSecure: true)
            }
        }
    }

    private func addPlugin() {
        draft.append(SloppyConfig.PluginConfig(title: "new-plugin", apiKey: "", apiUrl: "", plugin: ""))
        selectedIndex = draft.count - 1
    }

    private func removeSelected() {
        guard !draft.isEmpty else { return }
        draft.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func save() {
        var updated = config
        updated.plugins = draft
        onSave(updated)
    }
}
