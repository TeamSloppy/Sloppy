import SwiftUI
import SloppyClientUI

@MainActor
struct WorkspaceTerminalDrawerView<Host: View>: View {
    let height: CGFloat
    let canStartSession: Bool
    let onHeightChange: @MainActor (CGFloat) -> Void
    @ViewBuilder let host: () -> Host

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.colors.textMuted.opacity(0.45 as CGFloat))
                .frame(width: 42, height: 5)
                .padding(.vertical, theme.spacing.s)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onHeightChange(max(180, height - value.translation.height))
                        }
                )

            Divider()

            Group {
                if canStartSession {
                    host()
                } else {
                    VStack(spacing: theme.spacing.s) {
                        Text("Project directory unavailable")
                            .font(.system(size: theme.typography.body, weight: .medium))
                            .foregroundColor(theme.colors.textPrimary)
                        Text("Open the terminal from a project-backed tab to start a shell.")
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(theme.colors.surfaceRaised.opacity(0.92 as CGFloat))
    }
}
