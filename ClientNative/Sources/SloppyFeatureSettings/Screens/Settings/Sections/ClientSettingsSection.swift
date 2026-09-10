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
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionCard("Connection") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        serverDetails
                        Spacer(minLength: 0)
                        changeServerButton
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        serverDetails
                        changeServerButton
                    }
                }
                .padding(16)
            }

            SettingsSectionCard("Appearance") {
                HStack(spacing: 12) {
                    appearanceOption("Light", scheme: .light)
                    appearanceOption("Dark", scheme: .dark)
                }
                .padding(16)

                SettingsDivider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent color")
                        .font(.system(size: 13, weight: .medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(accentPresets, id: \.hex) { preset in
                            accentOption(preset)
                        }
                    }
                }
                .padding(16)

                SettingsDivider()
                SettingsFieldRow("Custom color", hint: "Hex color, e.g. #FF2D6F", text: Binding(
                    get: { settings.accentColorHex },
                    set: { settings.accentColorHex = $0 }
                ))
            }

            #if os(macOS)
            SettingsSectionCard("Desktop") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When the last window closes")
                        .font(.system(size: 13, weight: .medium))
                    Picker("When the last window closes", selection: Binding(
                        get: { settings.windowCloseBehavior },
                        set: { settings.windowCloseBehavior = $0 }
                    )) {
                        Text("Keep running").tag(ClientWindowCloseBehavior.keepProcess)
                        Text("Quit Sloppy").tag(ClientWindowCloseBehavior.quitOnLastWindow)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Keep Sloppy available in the menu bar after closing its windows.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            #endif
        }
    }

    private var serverDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Server", systemImage: "server.rack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(settings.serverHost)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Current server")
            Text("Changing server signs you out of the current session.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var changeServerButton: some View {
        Button(action: onChangeServer) {
            Label("Change Server", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fixedSize()
        .accessibilityIdentifier("settings.change-server")
    }

    private func appearanceOption(_ title: String, scheme: ClientColorScheme) -> some View {
        let selected = settings.colorScheme == scheme
        return Button {
            settings.colorScheme = scheme
        } label: {
            VStack(spacing: 10) {
                SettingsAppearancePreview(isDark: scheme == .dark, accent: theme.colors.accent)
                    .frame(height: 76)
                HStack(spacing: 6) {
                    Text(title)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? theme.colors.accent : .secondary)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(10)
            .background(selected ? theme.colors.accent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? theme.colors.accent : .primary.opacity(0.12),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(SettingsChoiceButtonStyle())
        .accessibilityLabel("\(title) appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(scheme.rawValue)")
    }

    private func accentOption(_ preset: (label: String, hex: String)) -> some View {
        let selected = settings.accentColorHex.caseInsensitiveCompare(preset.hex) == .orderedSame
        let color = Color.fromHex(UInt32(preset.hex.dropFirst(), radix: 16) ?? 0)
        return Button {
            settings.accentColorHex = preset.hex
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                Text(preset.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(SettingsChoiceButtonStyle())
        .help(preset.label)
        .accessibilityLabel("\(preset.label) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
