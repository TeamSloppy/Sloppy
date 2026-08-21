import SwiftUI
#if os(macOS)
import AppKit
#endif
import SloppyClientUI

@MainActor
struct WorkspaceBottomPanelDrawerView<Content: View>: View {
    let height: CGFloat
    let maximumHeight: CGFloat
    let selectedPanel: WorkspaceBottomPanelKind
    let onSelectPanel: @MainActor (WorkspaceBottomPanelKind) -> Void
    let onClose: @MainActor () -> Void
    let onHeightChange: @MainActor (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            panelBar
            Divider()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(theme.colors.surfaceRaised)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("workspace.bottom-panel")
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let startHeight = dragStartHeight ?? height
                        dragStartHeight = startHeight
                        onHeightChange(
                            min(maximumHeight, max(180, startHeight - value.translation.height))
                        )
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
            #if os(macOS)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.resizeUpDown.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            #endif
            .accessibilityLabel("Resize bottom panel")
    }

    private var panelBar: some View {
        HStack(spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: selectedPanel.systemImage)
                    .foregroundStyle(.secondary)

                Text(selectedPanel.title)
                    .font(.system(size: theme.typography.body, weight: .medium))
                    .lineLimit(1)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.typography.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close \(selectedPanel.title)")
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.colors.surface)
            )

            Menu {
                ForEach(WorkspaceBottomPanelKind.allCases) { panel in
                    Button {
                        onSelectPanel(panel)
                    } label: {
                        Label(panel.title, systemImage: panel.systemImage)
                    }
                    .disabled(panel == selectedPanel)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: theme.typography.body, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open bottom panel")

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: theme.typography.body))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close bottom panel")
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.bottom, theme.spacing.s)
    }
}

@MainActor
struct WorkspaceBottomPanelUnavailableView: View {
    let title: String
    let detail: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            Text(title)
                .font(.system(size: theme.typography.body, weight: .medium))
                .foregroundColor(theme.colors.textPrimary)
            Text(detail)
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
