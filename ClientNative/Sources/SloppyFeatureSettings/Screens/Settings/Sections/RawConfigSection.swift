import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct RawConfigSection: View {
    let config: SloppyConfig

    @Environment(\.theme) private var theme

    private var rawJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config),
              let json = String(data: data, encoding: .utf8) else {
            return "{ }"
        }
        return json
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("JSON") {
                ScrollView {
                    Text(rawJSON)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(c.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(sp.m)
                }
                .frame(height: 400)
            }

            Text("Read-only view. Use section editors above to modify config.")
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
        }
    }
}
