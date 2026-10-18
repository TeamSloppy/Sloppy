import SwiftUI
import SloppyClientUI

@MainActor
struct ProjectModeRail: View {
    let selectedSection: ProjectModeSection
    let onSelect: @MainActor (ProjectModeSection) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ProjectModeSection.allCases) { section in
                Button { onSelect(section) } label: {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 42, height: 42)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(ProjectModeRailButtonStyle(isSelected: selectedSection == section))
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .accessibilityIdentifier("project-mode-\(section.rawValue)")
                .help("\(section.title) (⌘\(String(section.shortcutCharacter)))")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.top, 12)
        .frame(width: 60)
        .background(theme.colors.surface)
        .overlay(alignment: .leading) { Divider() }
        .accessibilityIdentifier("project-mode-rail")
    }
}

struct ProjectModeRailButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
            .background(isSelected || isHovered ? theme.colors.surfaceRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered && !reduceMotion ? 1.10 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

#if os(macOS)
/// Project navigation lives alongside the other workspace summary blocks.
@MainActor
struct ProjectModeNavigationCard: View {
    let title: String
    let selectedSection: ProjectModeSection
    let onSelect: @MainActor (ProjectModeSection) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
            ForEach(ProjectModeSection.allCases) { section in
                Button { onSelect(section) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage).frame(width: 18)
                        Text(section.title)
                        Spacer(minLength: 0)
                        if selectedSection == section {
                            Image(systemName: "checkmark").font(.caption)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(selectedSection == section ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(selectedSection == section ? theme.colors.surfaceRaised : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                .accessibilityIdentifier("project-mode-\(section.rawValue)")
                .help("\(section.title) (⌘\(String(section.shortcutCharacter)))")
            }
        }
        .padding(14)
        .background(theme.colors.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.inspector.project-navigation")
    }
}
#endif
