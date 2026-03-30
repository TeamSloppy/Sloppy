import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProxySection: View {
    let config: SloppyConfig
    let onSave: (SloppyConfig) -> Void

    @State private var enabled: Bool
    @State private var type: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String

    private let proxyTypes = ["socks5", "http", "https"]

    init(config: SloppyConfig, onSave: @escaping (SloppyConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        let p = config.proxy
        self._enabled = State(initialValue: p.enabled)
        self._type = State(initialValue: p.type)
        self._host = State(initialValue: p.host)
        self._port = State(initialValue: String(p.port))
        self._username = State(initialValue: p.username)
        self._password = State(initialValue: p.password)
    }

    private var hasChanges: Bool {
        let p = config.proxy
        return enabled != p.enabled || type != p.type || host != p.host ||
            port != String(p.port) || username != p.username || password != p.password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Proxy", accentColor: Theme.accentCyan)

            SettingsSectionCard("Proxy Settings") {
                SettingsToggleRow(label: "Enabled", value: enabled) {
                    enabled.toggle()
                }

                if enabled {
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: Theme.spacingXS) {
                        Text("TYPE")
                            .font(.system(size: Theme.fontMicro))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: Theme.spacingS) {
                            ForEach(proxyTypes, id: \.self) { proxyType in
                                Button(proxyType) { type = proxyType }
                                    .font(.system(size: Theme.fontCaption))
                                    .foregroundColor(type == proxyType ? Theme.textPrimary : Theme.textMuted)
                                    .padding(.vertical, Theme.spacingXS)
                                    .padding(.horizontal, Theme.spacingS)
                                    .background(type == proxyType ? Theme.surfaceRaised : Color.clear)
                                    .border(type == proxyType ? Theme.borderBold : Theme.border, lineWidth: Theme.borderThin)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingS)
                    SettingsDivider()
                    SettingsFieldRow("Host", text: $host)
                    SettingsDivider()
                    SettingsFieldRow("Port", hint: "Default: 1080", text: $port)
                    SettingsDivider()
                    SettingsFieldRow("Username", text: $username)
                    SettingsDivider()
                    SettingsFieldRow("Password", text: $password, isSecure: true)
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
        let p = config.proxy
        enabled = p.enabled
        type = p.type
        host = p.host
        port = String(p.port)
        username = p.username
        password = p.password
    }

    private func save() {
        var updated = config
        updated.proxy.enabled = enabled
        updated.proxy.type = type
        updated.proxy.host = host
        updated.proxy.port = Int(port) ?? config.proxy.port
        updated.proxy.username = username
        updated.proxy.password = password
        onSave(updated)
    }
}
