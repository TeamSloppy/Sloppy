import SwiftUI
import SloppyClientCore
import SloppyClientUI

#if os(visionOS)
@MainActor
struct VisionFloatingTabBarView: View {
    let viewModel: MainViewModel
    let onOpenOverview: @MainActor () -> Void

    private let barHeight: CGFloat = 102
    private let maximumWidth: CGFloat = 960
    private let minimumTabWidth: CGFloat = 132
    private let maximumTabWidth: CGFloat = 220
    private let addButtonWidth: CGFloat = 48
    private let edgeEffectDistance: CGFloat = 140
    private let maximumEdgeBlur: CGFloat = 23

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { viewModel.selectNewChat() }) {
                    Image(systemName: "plus")
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)
                        .frame(width: addButtonWidth, height: addButtonWidth)
                }

                Spacer()

                Button(action: onOpenOverview) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)
                        .frame(width: addButtonWidth, height: addButtonWidth)
                }
            }
            .buttonStyle(
                VisionFloatingTabBarButtonStyle(in: .circle)
            )

            tabs
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.m)
        .frame(height: barHeight + theme.spacing.l)
        .glassBackgroundEffect()
    }

    private var tabs: some View {
        GeometryReader { geometry in
            let width = min(maximumWidth, geometry.size.width - theme.spacing.xxl * 2)
            let availableTabWidth = max(0, width - addButtonWidth - theme.spacing.m * 2)
            let stripFrame = geometry.frame(in: .global)

            HStack(spacing: theme.spacing.s) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing.xs) {
                        ForEach(viewModel.tabs) { tab in
                            VisionFloatingTabBarButton(
                                tab: tab,
                                isSelected: viewModel.selectedTabID == tab.id,
                                onSelect: { viewModel.selectTab(tab.id) },
                                onClose: { viewModel.closeTab(tab.id) }
                            )
                            .frame(width: tabWidth(for: availableTabWidth))
//                            .visualEffect { effect, proxy in
//                                let tabFrame = proxy.frame(in: .global)
//                                let edgeDistance = min(
//                                    max(0, tabFrame.minX - stripFrame.minX),
//                                    max(0, stripFrame.maxX - tabFrame.maxX)
//                                )
//                                let anchor: UnitPoint = tabFrame.midX < stripFrame.midX ? .leading : .trailing
//
//                                effect
//                                    .scaleEffect(
//                                        x: edgeCompression(for: edgeDistance),
//                                        y: 1,
//                                        anchor: anchor
//                                    )
//                                    .blur(radius: edgeBlurRadius(for: edgeDistance))
//                            }
                        }
                    }
                    .padding(.horizontal, theme.spacing.xs)
                }

                Button(action: onOpenOverview) {
                    Image(systemName: "rectangle.grid.1x2")
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)
                        .frame(width: addButtonWidth, height: addButtonWidth)
                }
                .buttonStyle(
                    VisionFloatingTabBarButtonStyle(in: .circle)
                )
            }
            .padding(.horizontal, theme.spacing.m)
        }
    }

    private func tabWidth(for availableWidth: CGFloat) -> CGFloat {
        guard !viewModel.tabs.isEmpty else {
            return minimumTabWidth
        }

        let totalSpacing = theme.spacing.xs * CGFloat(max(0, viewModel.tabs.count - 1))
        let rawWidth = (availableWidth - totalSpacing) / CGFloat(viewModel.tabs.count)
        return min(maximumTabWidth, max(minimumTabWidth, rawWidth))
    }

    private func edgeCompression(for distance: CGFloat) -> CGFloat {
        let progress = normalizedEdgeProgress(for: distance)
        return 0.82 + (0.18 * progress)
    }

    private func edgeBlurRadius(for distance: CGFloat) -> CGFloat {
        maximumEdgeBlur * (1 - normalizedEdgeProgress(for: distance))
    }

    private func normalizedEdgeProgress(for distance: CGFloat) -> CGFloat {
        min(max(distance / edgeEffectDistance, 0), 1)
    }
}

@MainActor
private struct VisionFloatingTabBarButton: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(tab.title)
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(isSelected ? Color.black : theme.colors.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.typography.micro, weight: .bold))
                        .foregroundColor(theme.colors.textSecondary.opacity(0.92 as CGFloat))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(
            VisionFloatingTabBarButtonStyle(
                isActive: isSelected,
                in: .capsule
            )
        )
    }
}

struct VisionFloatingTabBarButtonStyle<S: Shape>: ButtonStyle {

    let isActive: Bool
    let shape: S
    @Environment(\.theme) private var theme

    init(isActive: Bool = false, in shape: S) {
        self.isActive = isActive
        self.shape = shape
    }

    func makeBody(configuration: Configuration) -> some View {
        let backgroundColor = configuration.isPressed || isActive ?
        Color.white :
        theme.colors.surfaceRaised.opacity(0.42 as CGFloat)

        return configuration.label
            .padding(.horizontal, theme.spacing.l)
            .background {
                shape
                    .fill(backgroundColor)
                    .overlay {
                        shape
                            .stroke(Color.white.opacity(0.14 as CGFloat), lineWidth: 1)
                    }
            }
    }
}


#Preview {
    let viewModel = MainViewModel(
        endpoint: .direct(baseURL: .debugURL),
        settings: ClientSettings(),
        connectionMonitor: ConnectionMonitor(baseURL: .debugURL),
        onOpenSettings: { _ in },
        onOpenWorkspace: {}
    )

    viewModel.tabs = [
        .init(key: .chatSession(""), kind: .chat, title: "KDKDKDK", payload: .chatSession(sessionID: "", title: ""))
    ]

    return VisionFloatingTabBarView(viewModel: viewModel, onOpenOverview: {})
        .glassBackgroundEffect()
}
#endif
