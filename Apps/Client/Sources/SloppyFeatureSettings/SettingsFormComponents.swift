import AdaEngine
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
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: Theme.fontMicro))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingM)
                .padding(.bottom, Theme.spacingS)

            content()
        }
        .background(Theme.surface)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}

// MARK: - SettingsFieldRow

struct SettingsFieldRow: View {
    let label: String
    let hint: String?
    let binding: Binding<String>
    let isSecure: Bool

    init(_ label: String, hint: String? = nil, text: Binding<String>, isSecure: Bool = false) {
        self.label = label
        self.hint = hint
        self.binding = text
        self.isSecure = isSecure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text(label.uppercased())
                .font(.system(size: Theme.fontMicro))
                .foregroundColor(Theme.textSecondary)

            TextField(isSecure ? "••••••••" : label, text: binding)
                .font(.system(size: Theme.fontBody))
                .foregroundColor(Theme.textPrimary)
                .padding(Theme.spacingS)
                .background(Theme.bg)
                .border(Theme.border, lineWidth: Theme.borderThin)

            if let hint {
                Text(hint)
                    .font(.system(size: Theme.fontMicro))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let label: String
    let value: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button(value ? "ON" : "OFF") {
                onToggle()
            }
            .foregroundColor(value ? Theme.statusDone : Theme.textMuted)
            .font(.system(size: Theme.fontCaption))
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(Theme.surface)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}

// MARK: - SettingsDivider

struct SettingsDivider: View {
    var body: some View {
        Color.clear
            .frame(height: Theme.borderThin)
            .background(Theme.border)
    }
}

// MARK: - SettingsSaveBar

struct SettingsSaveBar: View {
    let hasChanges: Bool
    let statusText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Text(statusText)
                .font(.system(size: Theme.fontCaption))
                .foregroundColor(hasChanges ? Theme.statusWarning : Theme.textMuted)
            Spacer()
            if hasChanges {
                Button("CANCEL") { onCancel() }
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.textMuted)
                Button("SAVE") { onSave() }
                    .font(.system(size: Theme.fontCaption))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(Theme.surfaceRaised)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}
