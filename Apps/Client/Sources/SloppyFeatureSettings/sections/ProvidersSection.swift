import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProvidersSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: [SloppyConfig.ModelConfig]
    @State private var selectedIndex: Int = 0

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._draft = State(initialValue: config.models)
    }

    private var hasChanges: Bool {
        guard draft.count == config.models.count else { return true }
        for (index, model) in draft.enumerated() {
            let original = config.models[index]
            if model.title != original.title || model.apiKey != original.apiKey || model.apiUrl != original.apiUrl || model.model != original.model {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Providers", accentColor: Theme.accentCyan)

            if draft.isEmpty {
                Text("No providers configured.")
                    .font(.system(size: Theme.fontBody))
                    .foregroundColor(Theme.textMuted)
            } else {
                providerList
                if selectedIndex < draft.count {
                    providerEditor(index: selectedIndex)
                }
            }

            HStack(spacing: Theme.spacingS) {
                Button("+ ADD") { addProvider() }
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.accent)
                Spacer()
                if selectedIndex < draft.count && draft.count > 1 {
                    Button("REMOVE") { removeSelected() }
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.statusBlocked)
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { draft = config.models }
            )
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.enumerated()), id: \.offset) { index, model in
                Button(action: { selectedIndex = index }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.system(size: Theme.fontBody))
                                .foregroundColor(index == selectedIndex ? Theme.textPrimary : Theme.textSecondary)
                            Text(model.model)
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

    private func providerEditor(index: Int) -> some View {
        SettingsSectionCard("Edit Provider") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldRow("Title", text: Binding(
                    get: { draft[index].title },
                    set: { draft[index].title = $0 }
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
                SettingsDivider()
                SettingsFieldRow("Model", hint: "e.g. gpt-4.1-mini, claude-sonnet-4", text: Binding(
                    get: { draft[index].model },
                    set: { draft[index].model = $0 }
                ))
            }
        }
    }

    private func addProvider() {
        draft.append(SloppyConfig.ModelConfig(title: "new-provider", apiKey: "", apiUrl: "", model: ""))
        selectedIndex = draft.count - 1
    }

    private func removeSelected() {
        guard draft.count > 1 else { return }
        draft.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func save() {
        var updated = config
        updated.models = draft
        onSave(updated)
    }
}
