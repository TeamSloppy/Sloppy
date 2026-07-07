import SwiftUI
import SloppyClientCore
import SloppyClientUI
#if os(macOS)
import AppKit
#endif

@MainActor
struct DesktopWorkspaceTabStrip: View {
    @State var viewModel: MainViewModel

    private let stripHeight: CGFloat = 46
    private let minimumTabWidth: CGFloat = 120
    private let addButtonWidth: CGFloat = 30

    @State private var previousTabIDs: [WorkspaceTab.ID] = []
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let availableTabWidth = max(0, geometry.size.width - addButtonWidth - 2)
            let tabWidth = tabWidth(for: availableTabWidth)

            dragProtectedStrip(tabWidth: tabWidth)
        }
        .frame(height: stripHeight)
        .padding(.horizontal, theme.spacing.s)
        .padding(.vertical, theme.spacing.s)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.tabs.map(\.id))
    }

    @ViewBuilder
    private func dragProtectedStrip(tabWidth: CGFloat) -> some View {
#if os(macOS)
        WindowDragGestureShield {
            stripContent(tabWidth: tabWidth)
        }
#else
        stripContent(tabWidth: tabWidth)
#endif
    }

    private func stripContent(tabWidth: CGFloat) -> some View {
        let spacing: CGFloat = {
#if os(visionOS)
            theme.spacing.m
#else
            theme.spacing.xs
#endif
        }()
        return HStack(spacing: 2) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(viewModel.tabs) { tab in
                            DesktopWorkspaceTabButton(
                                tab: tab,
                                isSelected: viewModel.selectedTabID == tab.id,
                                onSelect: {
                                    viewModel.selectTab(tab.id)
                                },
                                onClose: {
                                    viewModel.closeTab(tab.id)
                                }
                            )
                            .frame(width: tabWidth)
                            .id(tab.id)
                            .draggable(tab.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first,
                                      let sourceTabID = UUID(uuidString: raw),
                                      sourceTabID != tab.id else {
                                    return false
                                }

                                viewModel.beginDesktopSplit(source: sourceTabID, target: tab.id)
                                return true
                            }
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )

#if !os(visionOS)
                            if viewModel.tabs.last != tab {
                                Divider()
                                    .fixedSize()
                            }
#endif
                        }
                    }
                    .padding(.horizontal, 2)
#if !os(visionOS)
                    .background {
                        Capsule()
                            .fill(.gray.opacity(0.3))
                    }
#endif
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

    private func tabWidth(for availableWidth: CGFloat) -> CGFloat {
        guard !viewModel.tabs.isEmpty else {
            return minimumTabWidth
        }

        let totalSpacing = theme.spacing.xs * CGFloat(max(0, viewModel.tabs.count - 1))
        let rawWidth = (availableWidth - totalSpacing - 4) / CGFloat(viewModel.tabs.count)
        return max(minimumTabWidth, rawWidth)
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

    private var selectedForegroundColor: Color {
#if os(visionOS)
        Color.black
#else
        theme.colors.textPrimary
#endif
    }

    private var defaultForegroundColor: Color {
#if os(visionOS)
        theme.colors.textSecondary.opacity(0.92 as CGFloat)
#else
        theme.colors.textSecondary.opacity(0.92 as CGFloat)
#endif
    }

    var body: some View {
        return Button(action: onSelect) {
            ZStack {
                Text(tab.title)
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(
                        isSelected ? selectedForegroundColor : defaultForegroundColor
                    )
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
                Capsule()
#if os(visionOS)
                    .fill(Color.white)
#else
                    .backportGlassEffect(Glass.regular, in: .capsule)
#endif
            } else if isHovered {
                Capsule()
#if os(visionOS)
                    .fill(theme.colors.surfaceGlow)
#else
                    .fill(Color.white.opacity(0.08 as CGFloat))
#endif
            } else {
#if os(visionOS)
                Capsule()
                    .fill(Material.regular.blendMode(.color))
#endif
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
//#if os(macOS)
//        .overlay {
//            MiddleClickCloseArea(onMiddleClick: onClose)
//        }
//#endif
        .onHover {
            self.isHovered = $0
        }
    }
}

#if os(macOS)
private struct WindowDragGestureShield<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WindowDragGestureShieldNSView<Content> {
        WindowDragGestureShieldNSView(rootView: content)
    }

    func updateNSView(_ nsView: WindowDragGestureShieldNSView<Content>, context: Context) {
        nsView.update(rootView: content)
    }
}

private final class WindowDragGestureShieldNSView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>

    override var mouseDownCanMoveWindow: Bool { false }

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
    }
}

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
        guard let event = NSApp.currentEvent else {
            return nil
        }

        switch event.type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return event.buttonNumber == 2 ? self : nil
        default:
            return super.hitTest(point)
        }
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
    @Previewable @State var viewModel = MainViewModel(
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
#if os(visionOS)
    .backportGlassEffect(.regular, in: .rect)
#endif
}
