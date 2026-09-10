import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ACPSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var enabled: Bool
    @State private var targets: [SloppyConfig.ACPTarget]
    @State private var selectedIndex: Int = 0
    @Environment(\.theme) private var theme

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._enabled = State(initialValue: config.acp.enabled)
        self._targets = State(initialValue: config.acp.targets)
    }

    private var hasChanges: Bool {
        enabled != config.acp.enabled || targets.count != config.acp.targets.count
    }

    var body: some View {
        let c = theme.colors
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Agent Communication Protocol") {
                SettingsToggleRow(label: "Enabled", value: enabled) {
                    enabled.toggle()
                }
            }

            if enabled {
                SettingsCollectionHeader(
                    title: "Configured targets", count: targets.count,
                    actionTitle: "Add Target", onAdd: addTarget
                )

                if targets.isEmpty {
                    Text("No ACP targets configured.")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textMuted)
                } else {
                    targetList
                    if selectedIndex < targets.count {
                        targetEditor(index: selectedIndex)
                    }
                }

                HStack {
                    Spacer()
                    if !targets.isEmpty {
                        Button("Remove", role: .destructive) { removeSelected() }
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.statusBlocked)
                    }
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { reset() }
            )
        }
    }

    private var targetList: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
            ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                SettingsSelectionTile(
                    title: target.title.isEmpty ? "Untitled" : target.title,
                    subtitle: target.command,
                    icon: "cpu",
                    isSelected: index == selectedIndex,
                    action: { selectedIndex = index }
                )
            }
        }
    }

    private func targetEditor(index: Int) -> some View {
        SettingsSectionCard("Target details") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldRow("ID", text: Binding(
                    get: { targets[index].id },
                    set: { targets[index].id = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("Title", text: Binding(
                    get: { targets[index].title },
                    set: { targets[index].title = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("Command", hint: "Executable path or command", text: Binding(
                    get: { targets[index].command },
                    set: { targets[index].command = $0 }
                ))
                SettingsDivider()
                SettingsToggleRow(label: "Enabled", value: targets[index].enabled) {
                    targets[index].enabled.toggle()
                }
            }
        }
    }

    private func addTarget() {
        let newTarget = SloppyConfig.ACPTarget(
            id: "target-\(targets.count + 1)",
            title: "New Target",
            command: "",
            enabled: true
        )
        targets.append(newTarget)
        selectedIndex = targets.count - 1
    }

    private func removeSelected() {
        guard !targets.isEmpty else { return }
        targets.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func reset() {
        enabled = config.acp.enabled
        targets = config.acp.targets
    }

    private func save() {
        var updated = config
        updated.acp.enabled = enabled
        updated.acp.targets = targets
        onSave(updated)
    }
}
