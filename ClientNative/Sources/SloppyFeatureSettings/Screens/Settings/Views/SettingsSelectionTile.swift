import SwiftUI
import SloppyClientUI

struct SettingsSelectionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? theme.colors.accent : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
#if os(iOS)
                        .font(.body)
#else
                        .font(.system(size: 13, weight: .medium))
#endif
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
#if os(iOS)
                            .font(.footnote)
#else
                            .font(.system(size: 12))
#endif
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? theme.colors.accent : .secondary.opacity(0.4))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
#if os(iOS)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
#else
            .background(isSelected ? theme.colors.accent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? theme.colors.accent.opacity(0.5) : .primary.opacity(0.08), lineWidth: 1)
            }
#endif
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(SettingsChoiceButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(subtitle.isEmpty ? title : "\(title) — \(subtitle)")
    }
}

struct SettingsCollectionHeader: View {
    let title: String
    let count: Int
    let actionTitle: String
    let onAdd: () -> Void

    var body: some View {
#if os(iOS)
        HStack(spacing: 8) {
            Text(title)
            Text(count.formatted())
                .monospacedDigit()
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAdd) {
                    Label(actionTitle, systemImage: "plus")
                }
                .accessibilityLabel(actionTitle)
            }
        }
#else
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(count.formatted())
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Label(actionTitle, systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
#endif
    }
}
