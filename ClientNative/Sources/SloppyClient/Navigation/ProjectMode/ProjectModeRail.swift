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
