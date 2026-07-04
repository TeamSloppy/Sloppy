import SwiftUI
import SloppyClientCore
import SloppyClientUI
#if os(macOS)
import AppKit
#endif

@MainActor
struct DesktopWorkspaceTabStrip: View {
    let viewModel: MainViewModel

    private let stripHeight: CGFloat = 46
    private let minimumTabWidth: CGFloat = 120
    private let addButtonWidth: CGFloat = 30

    @State private var previousTabIDs: [WorkspaceTab.ID] = []
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let availableTabWidth = max(0, geometry.size.width - addButtonWidth - 2)
            let tabWidth = tabWidth(for: availableTabWidth)

            HStack(spacing: 2) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: theme.spacing.xs) {
                            ForEach(viewModel.tabs) { tab in
                                DesktopWorkspaceTabButton(
                                    tab: tab,
                                    isSelected: viewModel.selectedTabID == tab.id,
                                    onSelect: { viewModel.selectTab(tab.id) },
                                    onClose: { viewModel.closeTab(tab.id) }
                                )
                                .frame(width: tabWidth)
                                .id(tab.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )

                                if viewModel.tabs.last != tab {
                                    Divider()
                                        .fixedSize()
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .background {
                            Capsule()
                                .fill(.gray.opacity(0.3))
                        }
                    }
                    .clipShape(Capsule())
                    .onAppear {
                        previousTabIDs = viewModel.tabs.map(\.id)
                    }
                    .onChange(of: viewModel.tabs.map(\.id)) { _, newIDs in
                        let newTabIDs = newIDs.filter { !previousTabIDs.contains($0) }
                        previousTabIDs = newIDs

                        guard let tabID = newTabIDs.last else {
                            return
                        }

                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            proxy.scrollTo(tabID, anchor: .trailing)
                        }
                    }
                }

                Button(action: { viewModel.createBlankChatTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: theme.typography.caption, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary.opacity(0.94 as CGFloat))
                        .frame(width: addButtonWidth, height: 30)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: stripHeight)
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, theme.spacing.s)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.tabs.map(\.id))
    }

    private func tabWidth(for availableWidth: CGFloat) -> CGFloat {
        guard !viewModel.tabs.isEmpty else {
            return minimumTabWidth
        }

        let totalSpacing = theme.spacing.xs * CGFloat(max(0, viewModel.tabs.count - 1))
        let rawWidth = (availableWidth - totalSpacing - 4) / CGFloat(viewModel.tabs.count)
        return max(minimumTabWidth, rawWidth)
    }

    private var safariGlassBarBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12 as CGFloat),
                theme.colors.surfaceRaised.opacity(0.88 as CGFloat),
                Color.black.opacity(0.36 as CGFloat)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var safariChromeButtonFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.16 as CGFloat),
                theme.colors.surfaceRaised.opacity(0.92 as CGFloat),
                Color.black.opacity(0.26 as CGFloat)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

@MainActor
private struct DesktopWorkspaceTabButton: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    @State private var isHovered = false

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Text(tab.title)
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary.opacity(0.92 as CGFloat))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.vertical, theme.spacing.s)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                if #available(iOS 26, macOS 26, *) {
                    Capsule()
                    #if !os(visionOS)
                        .glassEffect(Glass.regular, in: .capsule)
                    #else
                        .fill(safariIdleTabFill)
                    #endif
                } else {
                    Capsule()
                        .fill(safariIdleTabFill)
                }
            } else if isHovered {
                Capsule()
                    .fill(Color.white.opacity(0.08 as CGFloat))
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            HStack(spacing: 0) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.typography.micro, weight: .bold))
                        .foregroundColor(isSelected ? theme.colors.textPrimary.opacity(0.94 as CGFloat) : theme.colors.textSecondary.opacity(0.9 as CGFloat))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .opacity(Double((isHovered || isSelected) ? 1 : 0))

                Color.clear
                    .frame(width: 18, height: 18)
                    .allowsHitTesting(false)
            }
            .frame(width: 36, alignment: .leading)
        }
        .overlay {
#if os(macOS)
            MiddleClickCloseArea(onMiddleClick: onClose)
#endif
        }
        .onHover {
            self.isHovered = $0
        }
    }

    private var safariSelectedTabFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.16 as CGFloat),
                theme.colors.surfaceRaised.opacity(0.96 as CGFloat),
                Color.black.opacity(0.3 as CGFloat)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var safariIdleTabFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.04 as CGFloat),
                theme.colors.surface.opacity(0.54 as CGFloat),
                Color.black.opacity(0.18 as CGFloat)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var safariCloseButtonFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isSelected ? 0.12 as CGFloat : 0.08 as CGFloat),
                theme.colors.surface.opacity(isSelected ? 0.5 as CGFloat : 0.38 as CGFloat)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#if os(macOS)
private struct MiddleClickCloseArea: NSViewRepresentable {
    let onMiddleClick: @MainActor () -> Void

    func makeNSView(context: Context) -> MiddleClickCloseNSView {
        let view = MiddleClickCloseNSView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: MiddleClickCloseNSView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }
}

private final class MiddleClickCloseNSView: NSView {
    var onMiddleClick: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseUp(with: event)
            return
        }

        guard let onMiddleClick else {
            return
        }

        Task { @MainActor in
            onMiddleClick()
        }
    }
}
#endif

#Preview {
    let viewModel = MainViewModel(
        baseURL: .debugURL,
        settings: ClientSettings(),
        connectionMonitor: ConnectionMonitor(baseURL: .debugURL),
        onOpenSettings: {},
        onOpenWorkspace: {}
    )

    viewModel.tabs = [
        .init(key: .chatSession(""), kind: .chat, title: "ewfe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewfwefqwef", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
        .init(key: .chatSession(""), kind: .chat, title: "ewqwefqweffe", payload: .chatSession(sessionID: "", title: "")),
    ]

    return DesktopWorkspaceTabStrip(
        viewModel: viewModel
    )
    .frame(width: 700)
}
