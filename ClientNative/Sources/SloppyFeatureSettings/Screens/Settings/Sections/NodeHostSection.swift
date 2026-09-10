import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct NodeHostSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var nodesText: String

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._nodesText = State(initialValue: config.nodes.map(\.id).joined(separator: "\n"))
    }

    private var hasChanges: Bool {
        parsedNodeIDs != config.nodes.map(\.id)
    }

    private var parsedNodeIDs: [String] {
        nodesText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Nodes") {
                SettingsMultilineFieldRow("Node IDs", hint: "One node per line. Default: local", text: $nodesText)
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { nodesText = config.nodes.map(\.id).joined(separator: "\n") }
            )
        }
    }

    private func save() {
        var updated = config
        updated.nodes = parsedNodeIDs.map { id in
            config.nodes.first(where: { $0.id == id })
                ?? SloppyConfig.Node(id: id, title: id, kind: id == "local" ? "local" : "legacy")
        }
        onSave(updated)
    }
}
