import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct NodeHostSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var nodesText: String
    @Environment(\.theme) private var theme

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
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Node Host", accentColor: c.accentCyan)

            SettingsSectionCard("Nodes") {
                VStack(alignment: .leading, spacing: sp.xs) {
                    Text("NODES")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textSecondary)
                        .padding(.horizontal, sp.m)
                        .padding(.top, sp.s)

                    TextField("local", text: $nodesText)
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
                        .padding(sp.s)
                        .background(c.background)
                        .border(c.border, lineWidth: bo.thin)
                        .padding(.horizontal, sp.m)

                    Text("One node per line. Default: local")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textMuted)
                        .padding(.horizontal, sp.m)
                        .padding(.bottom, sp.s)
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
