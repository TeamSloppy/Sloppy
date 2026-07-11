import Foundation
import SwiftUI
import SloppyClientUI

// MARK: - SettingsSectionCard

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: () -> Content

    @Environment(\.theme) private var theme

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.s) {
            Text(title)
                .font(.system(size: ty.caption, weight: .semibold))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.xs)

            content()
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

            TextField(isSecure ? "••••••••" : label, text: binding)
                .font(.system(size: ty.body))
                .textFieldStyle(.roundedBorder)

            if let hint {
                Text(hint)
                    .font(.system(size: ty.micro))
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
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.xs)
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
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Text(statusText)
                .font(.system(size: ty.caption))
                .foregroundColor(hasChanges ? c.statusWarning : c.textMuted)
            Spacer()
            if hasChanges {
                Button("CANCEL") { onCancel() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Button("SAVE") { onSave() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accent)
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
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
            .padding(.vertical, theme.spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
