import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct PluginsSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: [SloppyConfig.PluginConfig]
    @State private var selectedIndex: Int = 0
    @Environment(\.theme) private var theme

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
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 24) {
            SettingsCollectionHeader(
                title: "Configured plugins", count: draft.count,
                actionTitle: "Add Plugin", onAdd: addPlugin
            )

            if draft.isEmpty {
                Text("No plugins configured.")
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textMuted)
            } else {
                pluginList
                if selectedIndex < draft.count {
                    pluginEditor(index: selectedIndex)
                }
            }

            HStack(spacing: sp.s) {
                Spacer()
                if selectedIndex < draft.count && !draft.isEmpty {
                    Button("Remove", role: .destructive) { removeSelected() }
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.statusBlocked)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
            ForEach(Array(draft.enumerated()), id: \.offset) { index, plugin in
                SettingsSelectionTile(
                    title: plugin.title.isEmpty ? "Untitled" : plugin.title,
                    subtitle: plugin.plugin,
                    icon: "puzzlepiece.extension",
                    isSelected: index == selectedIndex,
                    action: { selectedIndex = index }
                )
            }
        }
    }

    private func pluginEditor(index: Int) -> some View {
        SettingsSectionCard("Plugin details") {
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
