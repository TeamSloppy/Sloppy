import Foundation
import SwiftUI
import SloppyClientUI

// MARK: - SettingsSectionCard

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .modifier(SettingsCardBackground())
        }
    }
}

// MARK: - SettingsFieldRow

struct SettingsFieldRow: View {
    let label: String
    let hint: String?
    let binding: Binding<String>
    let isSecure: Bool

    @Environment(\.theme) private var theme

    init(_ label: String, hint: String? = nil, text: Binding<String>, isSecure: Bool = false) {
        self.label = label
        self.hint = hint
        self.binding = text
        self.isSecure = isSecure
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.xs) {
            Text(label)
                .font(.system(size: ty.caption, weight: .medium))
                .foregroundColor(c.textSecondary)

            Group {
                if isSecure {
                    SecureField(label, text: binding, prompt: Text("••••••••"))
                } else {
                    TextField(label, text: binding, prompt: Text(""))
                }
            }
            .labelsHidden()
            .accessibilityLabel(label)
            .font(.system(size: ty.body))
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)

            if let hint {
                Text(hint)
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let label: String
    let value: Bool
    let onToggle: () -> Void

    @Environment(\.theme) private var theme

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { value },
            set: { _ in onToggle() }
        )
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Text(label)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
            Spacer(minLength: 0)
            Toggle(isOn: toggleBinding) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(label)
            .toggleStyle(.switch)
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, 12)
    }
}

// MARK: - SettingsDivider

struct SettingsDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors

        return Divider()
            .overlay(c.border.opacity(0.55 as CGFloat))
    }
}

// MARK: - SettingsSaveBar

struct SettingsSaveBar: View {
    let hasChanges: Bool
    let statusText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        if hasChanges {
            HStack(spacing: 12) {
                Label(statusText, systemImage: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save Changes", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }
}

struct SettingsSectionSurface<Content: View>: View {
    let content: Content

    @Environment(\.theme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsCardBackground())
    }
}

private struct SettingsCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(white: colorScheme == .dark ? 0.12 : 1),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct SettingsMultilineFieldRow: View {
    let label: String
    let hint: String?
    @Binding var text: String

    init(_ label: String, hint: String? = nil, text: Binding<String>) {
        self.label = label
        self.hint = hint
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 160)
                .padding(8)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                }
                .accessibilityLabel(label)
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
