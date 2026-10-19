#if os(macOS)
import SwiftUI
import SloppyClientUI

struct DesktopSettingsLayout<Sidebar: View, Detail: View>: View {
    let onDismiss: (() -> Void)?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 18, weight: .semibold))
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close settings")
                    .accessibilityIdentifier("settings.close")
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
            Divider().overlay(theme.colors.border)
            HStack(spacing: 0) {
                sidebar()
                    .frame(width: 216)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(theme.colors.surfaceGlass)
                Divider().overlay(theme.colors.border)
                detail().frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.colors.background)
        .frame(minWidth: 860, idealWidth: 980, maxWidth: .infinity,
               minHeight: 620, idealHeight: 740, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.desktop-dialog")
    }
}

struct DesktopSettingsSidebar: View {
    @Binding var selection: SettingsScreenSection?
    @Binding var query: String
    let sections: [SettingsScreenSection]
    @State private var expandedGroups: Set<SettingsScreenSectionGroup> = []
    @Environment(\.theme) private var theme

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            SettingsSearchField(text: $query).padding(.horizontal, 12).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sections.filter { $0.group == .client }) { section in row(section) }
                    ForEach([SettingsScreenSectionGroup.config, .advanced], id: \.self) { group in
                        let matches = sections.filter { $0.group == group }
                        if !matches.isEmpty {
                            DisclosureGroup(isExpanded: expansion(for: group)) {
                                VStack(spacing: 4) {
                                    ForEach(matches) { section in row(section) }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text(group == .config ? "Configuration" : "Advanced")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.colors.textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("settings.group.\(group.rawValue)")
                        }
                    }
                    if sections.isEmpty {
                        Text("No matching settings").font(.callout)
                            .foregroundStyle(theme.colors.textMuted).padding(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                let visible = sections.filter { $0.group == .client || expandedGroups.contains($0.group) || isSearching }
                guard !visible.isEmpty, direction == .up || direction == .down else { return }
                let index = visible.firstIndex { $0 == selection }
                let next = direction == .down ? min((index ?? -1) + 1, visible.count - 1) : max((index ?? 1) - 1, 0)
                selection = visible[next]
            }
        }
        .onChange(of: selection, initial: true) { _, section in
            if let section, section.group != .client { expandedGroups.insert(section.group) }
        }
    }

    private func expansion(for group: SettingsScreenSectionGroup) -> Binding<Bool> {
        Binding(get: { isSearching || expandedGroups.contains(group) }, set: { expanded in
            if expanded { expandedGroups.insert(group) } else { expandedGroups.remove(group) }
        })
    }

    private func row(_ section: SettingsScreenSection) -> some View {
        DesktopSettingsNavigationRow(title: section.title, isSelected: selection == section) {
            selection = section
        }
        .accessibilityIdentifier("settings.section.\(section.rawValue)")
    }
}

private struct DesktopSettingsNavigationRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(isSelected ? theme.colors.surfaceRaised : isHovered ? theme.colors.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
#endif
