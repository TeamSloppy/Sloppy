import AdaEngine
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
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: ty.micro))
                .foregroundColor(c.textMuted)
                .padding(.horizontal, sp.m)
                .padding(.top, sp.m)
                .padding(.bottom, sp.s)

            content()
        }
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
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
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.xs) {
            Text(label.uppercased())
                .font(.system(size: ty.micro))
                .foregroundColor(c.textSecondary)

            TextField(isSecure ? "••••••••" : label, text: binding)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .padding(sp.s)
                .background(c.background)
                .border(c.border, lineWidth: bo.thin)

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

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack {
            Text(label.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textPrimary)
            Spacer()
            Button(value ? "ON" : "OFF") {
                onToggle()
            }
            .foregroundColor(value ? c.statusDone : c.textMuted)
            .font(.system(size: ty.caption))
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
    }
}

// MARK: - SettingsDivider

struct SettingsDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let bo = theme.borders

        return Color.clear
            .frame(height: bo.thin)
            .background(c.border)
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
        let bo = theme.borders
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
        .background(c.surfaceRaised)
        .border(c.border, lineWidth: bo.thin)
    }
}
