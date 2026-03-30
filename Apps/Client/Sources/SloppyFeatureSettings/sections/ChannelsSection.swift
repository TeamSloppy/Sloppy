import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ChannelsSection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var telegramEnabled: Bool
    @State private var telegramBotToken: String
    @State private var discordEnabled: Bool
    @State private var discordBotToken: String
    @State private var discordGuildId: String

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        self._telegramEnabled = State(initialValue: config.channels.telegram != nil)
        self._telegramBotToken = State(initialValue: config.channels.telegram?.botToken ?? "")
        self._discordEnabled = State(initialValue: config.channels.discord != nil)
        self._discordBotToken = State(initialValue: config.channels.discord?.botToken ?? "")
        self._discordGuildId = State(initialValue: config.channels.discord?.guildId ?? "")
    }

    private var hasChanges: Bool {
        telegramEnabled != (config.channels.telegram != nil) ||
        telegramBotToken != (config.channels.telegram?.botToken ?? "") ||
        discordEnabled != (config.channels.discord != nil) ||
        discordBotToken != (config.channels.discord?.botToken ?? "") ||
        discordGuildId != (config.channels.discord?.guildId ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Channels", accentColor: Theme.accentCyan)

            SettingsSectionCard("Telegram") {
                SettingsToggleRow(label: "Enabled", value: telegramEnabled) {
                    telegramEnabled.toggle()
                }
                if telegramEnabled {
                    SettingsDivider()
                    SettingsFieldRow("Bot Token", hint: "Telegram bot token from @BotFather", text: $telegramBotToken, isSecure: true)
                }
            }

            SettingsSectionCard("Discord") {
                SettingsToggleRow(label: "Enabled", value: discordEnabled) {
                    discordEnabled.toggle()
                }
                if discordEnabled {
                    SettingsDivider()
                    SettingsFieldRow("Bot Token", hint: "Discord bot token", text: $discordBotToken, isSecure: true)
                    SettingsDivider()
                    SettingsFieldRow("Guild ID", hint: "Discord server/guild ID", text: $discordGuildId)
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

    private func reset() {
        telegramEnabled = config.channels.telegram != nil
        telegramBotToken = config.channels.telegram?.botToken ?? ""
        discordEnabled = config.channels.discord != nil
        discordBotToken = config.channels.discord?.botToken ?? ""
        discordGuildId = config.channels.discord?.guildId ?? ""
    }

    private func save() {
        var updated = config
        updated.channels.telegram = telegramEnabled ? SloppyConfig.ChannelConfig.Telegram(botToken: telegramBotToken) : nil
        updated.channels.discord = discordEnabled ? SloppyConfig.ChannelConfig.Discord(botToken: discordBotToken, guildId: discordGuildId) : nil
        onSave(updated)
    }
}
