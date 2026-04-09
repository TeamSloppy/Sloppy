import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProvidersSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var draft: [SloppyConfig.ModelConfig]
    @State private var selectedIndex: Int = 0
    @Environment(\.theme) private var theme

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
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Providers", accentColor: c.accentCyan)

            if draft.isEmpty {
                Text("No providers configured.")
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textMuted)
            } else {
                providerList
                if selectedIndex < draft.count {
                    providerEditor(index: selectedIndex)
                }
            }

            HStack(spacing: sp.s) {
                Button("+ ADD") { addProvider() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accent)
                Spacer()
                if selectedIndex < draft.count && draft.count > 1 {
                    Button("REMOVE") { removeSelected() }
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.statusBlocked)
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
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.enumerated()), id: \.offset) { index, model in
                Button(action: { selectedIndex = index }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.system(size: ty.body))
                                .foregroundColor(index == selectedIndex ? c.textPrimary : c.textSecondary)
                            Text(model.model)
                                .font(.system(size: ty.micro))
                                .foregroundColor(c.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
                    .background(index == selectedIndex ? c.surfaceRaised : Color.clear)
                    .border(c.border, lineWidth: bo.thin)
                }
            }
        }
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
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
                SettingsFieldRow("Model", hint: "e.g. gpt-5.4-mini, claude-sonnet-4", text: Binding(
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
