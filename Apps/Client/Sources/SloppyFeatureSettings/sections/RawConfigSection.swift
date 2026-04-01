import AdaEngine
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

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Raw Config", accentColor: c.accentCyan)

            SettingsSectionCard("JSON") {
                ScrollView {
                    Text(rawJSON)
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textSecondary)
                        .padding(sp.m)
                }
                .frame(height: 400)
            }

            Text("Read-only view. Use section editors above to modify config.")
                .font(.system(size: ty.micro))
                .foregroundColor(c.textMuted)
        }
    }
}
