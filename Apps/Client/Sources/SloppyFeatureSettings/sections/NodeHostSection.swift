import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct NodeHostSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var nodesText: String

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._nodesText = State(initialValue: config.nodes.joined(separator: "\n"))
    }

    private var hasChanges: Bool {
        parsedNodes != config.nodes
    }

    private var parsedNodes: [String] {
        nodesText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Node Host", accentColor: Theme.accentCyan)

            SettingsSectionCard("Nodes") {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    Text("NODES")
                        .font(.system(size: Theme.fontMicro))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, Theme.spacingM)
                        .padding(.top, Theme.spacingS)

                    TextField("local", text: $nodesText)
                        .font(.system(size: Theme.fontBody))
                        .foregroundColor(Theme.textPrimary)
                        .padding(Theme.spacingS)
                        .background(Theme.bg)
                        .border(Theme.border, lineWidth: Theme.borderThin)
                        .padding(.horizontal, Theme.spacingM)

                    Text("One node per line. Default: local")
                        .font(.system(size: Theme.fontMicro))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, Theme.spacingM)
                        .padding(.bottom, Theme.spacingS)
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { nodesText = config.nodes.joined(separator: "\n") }
            )
        }
    }

    private func save() {
        var updated = config
        updated.nodes = parsedNodes
        onSave(updated)
    }
}
