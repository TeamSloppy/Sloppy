import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct RawConfigSection: View {
    let config: SloppyConfig

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
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Raw Config", accentColor: Theme.accentCyan)

            SettingsSectionCard("JSON") {
                ScrollView {
                    Text(rawJSON)
                        .font(.system(size: Theme.fontMicro))
                        .foregroundColor(Theme.textSecondary)
                        .padding(Theme.spacingM)
                }
                .frame(height: 400)
            }

            Text("Read-only view. Use section editors above to modify config.")
                .font(.system(size: Theme.fontMicro))
                .foregroundColor(Theme.textMuted)
        }
    }
}
