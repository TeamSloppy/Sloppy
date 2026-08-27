import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ClientSettingsSection: View {
    let settings: ClientSettings
    let onChangeServer: @MainActor () -> Void

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
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: sp.m) {
            SettingsSectionCard("Connection") {
                VStack(alignment: .leading, spacing: sp.s) {
                    Text("SERVER")
                        .font(.system(size: theme.typography.micro))
                        .foregroundColor(theme.colors.textSecondary)
                    Text(settings.serverHost)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(theme.colors.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Current server")
                    Text("Changing server signs you out of the current session.")
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)

                SettingsDivider()

                Button(action: onChangeServer) {
                    Label("Change Server", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .accessibilityIdentifier("settings.change-server")
            }
            .padding(.horizontal, sp.m)

            SettingsSectionCard("Appearance") {
                colorSchemePicker
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
    }

    private var colorSchemePicker: some View {
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: sp.s) {
                colorSchemeButton("Light", scheme: .light)
                colorSchemeButton("Dark", scheme: .dark)
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)
        }
    }

    private func colorSchemeButton(_ title: String, scheme: ClientColorScheme) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography
        let selected = settings.colorScheme == scheme

        return Button(title) {
            settings.colorScheme = scheme
        }
        .font(.system(size: ty.caption))
        .foregroundColor(selected ? c.textPrimary : c.textMuted)
        .padding(.vertical, sp.xs)
        .padding(.horizontal, sp.s)
        .background(selected ? c.surfaceRaised.opacity(0.5 as CGFloat) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? c.borderBold.opacity(0.5 as CGFloat) : c.border.opacity(0.35 as CGFloat), lineWidth: bo.thin)
        )
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
                    .background(settings.accentColorHex == preset.hex ? c.surfaceRaised.opacity(0.45 as CGFloat) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(settings.accentColorHex == preset.hex ? c.borderBold.opacity(0.45 as CGFloat) : c.border.opacity(0.3 as CGFloat), lineWidth: bo.thin)
                    )
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
                    desktopCloseButton("Keep Process", behavior: .keepProcess)
                    desktopCloseButton("Quit On Last Window", behavior: .quitOnLastWindow)
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
        .background(selected ? c.surfaceRaised.opacity(0.5 as CGFloat) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? c.borderBold.opacity(0.45 as CGFloat) : c.border.opacity(0.3 as CGFloat), lineWidth: bo.thin)
        )
    }
    #endif
}
