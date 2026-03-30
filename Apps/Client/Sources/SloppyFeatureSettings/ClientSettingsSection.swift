import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ClientSettingsSection: View {
    let settings: ClientSettings

    @State private var hostDraft: String = ""
    @State private var portDraft: String = ""

    private let accentPresets: [(label: String, hex: String)] = [
        ("Pink", "#FF2D6F"),
        ("Cyan", "#00F0FF"),
        ("Acid", "#CDFF00"),
        ("Green", "#4ADE80"),
        ("Orange", "#FFAA00"),
        ("White", "#F0F0F0")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            SectionHeader("Client", accentColor: Theme.accent)
                .padding(.horizontal, Theme.spacingM)

            SettingsSectionCard("Connection") {
                SettingsFieldRow("Host", hint: "Sloppy server hostname or IP", text: Binding(
                    get: { hostDraft },
                    set: { hostDraft = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("Port", hint: "Default: 25101", text: Binding(
                    get: { portDraft },
                    set: { portDraft = $0 }
                ))
                SettingsDivider()
                HStack(spacing: Theme.spacingM) {
                    Spacer()
                    Button("APPLY") { applyConnection() }
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.accent)
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingS)
            }
            .padding(.horizontal, Theme.spacingM)

            SettingsSectionCard("Accent Color") {
                accentColorPicker
            }
            .padding(.horizontal, Theme.spacingM)

            #if os(macOS)
            desktopSettingsSection
            #endif
        }
        .onAppear {
            hostDraft = settings.serverHost
            portDraft = String(settings.serverPort)
        }
    }

    private var accentColorPicker: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack(spacing: Theme.spacingS) {
                ForEach(accentPresets, id: \.hex) { preset in
                    Button(preset.label) {
                        settings.accentColorHex = preset.hex
                    }
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(settings.accentColorHex == preset.hex ? Theme.textPrimary : Theme.textMuted)
                    .padding(.vertical, Theme.spacingXS)
                    .padding(.horizontal, Theme.spacingS)
                    .background(settings.accentColorHex == preset.hex ? Theme.surfaceRaised : Color.clear)
                    .border(settings.accentColorHex == preset.hex ? Theme.borderBold : Theme.border, lineWidth: Theme.borderThin)
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS)

            SettingsDivider()
            SettingsFieldRow("Custom Hex", hint: "e.g. #FF2D6F", text: Binding(
                get: { settings.accentColorHex },
                set: { settings.accentColorHex = $0 }
            ))
        }
    }

    private func applyConnection() {
        settings.serverHost = hostDraft.trimmingCharacters(in: .whitespaces)
        if let port = Int(portDraft.trimmingCharacters(in: .whitespaces)), port > 0 {
            settings.serverPort = port
        }
    }

    #if os(macOS)
    private var desktopSettingsSection: some View {
        SettingsSectionCard("Desktop") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("DESKTOP-SPECIFIC SETTINGS")
                        .font(.system(size: Theme.fontCaption))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.vertical, Theme.spacingS)
            }
        }
        .padding(.horizontal, Theme.spacingM)
    }
    #endif
}
