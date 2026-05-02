import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ClientSettingsSection: View {
    let settings: ClientSettings

    @State private var hostDraft: String = ""
    @State private var portDraft: String = ""
    @Environment(\.theme) private var theme

    private let accentPresets: [(label: String, hex: String)] = [
        ("Pink", "#FF2D6F"),
        ("Cyan", "#00F0FF"),
        ("Acid", "#CDFF00"),
        ("Green", "#4ADE80"),
        ("Orange", "#FFAA00"),
        ("White", "#F0F0F0")
    ]

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Client", accentColor: c.accent)
                .padding(.horizontal, sp.m)

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
                HStack(spacing: sp.m) {
                    Spacer()
                    Button("APPLY") { applyConnection() }
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.accent)
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
            }
            .padding(.horizontal, sp.m)

            SettingsSectionCard("Accent Color") {
                accentColorPicker
            }
            .padding(.horizontal, sp.m)

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
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            HStack(spacing: sp.s) {
                ForEach(accentPresets, id: \.hex) { preset in
                    Button(preset.label) {
                        settings.accentColorHex = preset.hex
                    }
                    .font(.system(size: ty.caption))
                    .foregroundColor(settings.accentColorHex == preset.hex ? c.textPrimary : c.textMuted)
                    .padding(.vertical, sp.xs)
                    .padding(.horizontal, sp.s)
                    .background(settings.accentColorHex == preset.hex ? c.surfaceRaised : Color.clear)
                    .border(settings.accentColorHex == preset.hex ? c.borderBold : c.border, lineWidth: bo.thin)
                }
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)

            SettingsDivider()
            SettingsFieldRow("Custom Hex", hint: "e.g. #FF2D6F", text: Binding(
                get: { settings.accentColorHex },
                set: { settings.accentColorHex = $0 }
            ))
        }
    }

    private func applyConnection() {
        guard let address = ServerAddress.parse(host: hostDraft, port: portDraft) else { return }
        hostDraft = address.host
        portDraft = String(address.port)
        settings.serverHost = address.host
        settings.serverPort = address.port
    }

    #if os(macOS)
    private var desktopSettingsSection: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return SettingsSectionCard("Desktop") {
            VStack(alignment: .leading, spacing: 0) {
                Text("WINDOW CLOSE")
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textSecondary)
                    .padding(.horizontal, sp.m)
                    .padding(.top, sp.s)

                HStack(spacing: sp.s) {
                    desktopCloseButton("KEEP PROCESS", behavior: .keepProcess)
                    desktopCloseButton("QUIT WHEN LAST WINDOW CLOSES", behavior: .quitOnLastWindow)
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
            }
        }
        .padding(.horizontal, sp.m)
    }

    private func desktopCloseButton(_ title: String, behavior: ClientWindowCloseBehavior) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography
        let selected = settings.windowCloseBehavior == behavior

        return Button(title) {
            settings.windowCloseBehavior = behavior
        }
        .font(.system(size: ty.caption))
        .foregroundColor(selected ? c.textPrimary : c.textMuted)
        .padding(.vertical, sp.xs)
        .padding(.horizontal, sp.s)
        .background(selected ? c.surfaceRaised : Color.clear)
        .border(selected ? c.borderBold : c.border, lineWidth: bo.thin)
    }
    #endif
}
