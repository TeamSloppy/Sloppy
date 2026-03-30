import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ACPSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var enabled: Bool
    @State private var targets: [SloppyConfig.ACPTarget]
    @State private var selectedIndex: Int = 0

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
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("ACP", accentColor: Theme.accentCyan)

            SettingsSectionCard("Agent Communication Protocol") {
                SettingsToggleRow(label: "Enabled", value: enabled) {
                    enabled.toggle()
                }
            }

            if enabled {
                if targets.isEmpty {
                    Text("No ACP targets configured.")
                        .font(.system(size: Theme.fontBody))
                        .foregroundColor(Theme.textMuted)
                } else {
                    targetList
                    if selectedIndex < targets.count {
                        targetEditor(index: selectedIndex)
                    }
                }

                HStack {
                    Button("+ ADD TARGET") { addTarget() }
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.accent)
                    Spacer()
                    if !targets.isEmpty {
                        Button("REMOVE") { removeSelected() }
                            .font(.system(size: Theme.fontCaption))
                            .foregroundColor(Theme.statusBlocked)
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                Button(action: { selectedIndex = index }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.title)
                                .font(.system(size: Theme.fontBody))
                                .foregroundColor(index == selectedIndex ? Theme.textPrimary : Theme.textSecondary)
                            Text(target.command)
                                .font(.system(size: Theme.fontMicro))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        if !target.enabled {
                            Text("DISABLED")
                                .font(.system(size: Theme.fontMicro))
                                .foregroundColor(Theme.textMuted)
                        }
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

    private func targetEditor(index: Int) -> some View {
        SettingsSectionCard("Edit Target") {
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
