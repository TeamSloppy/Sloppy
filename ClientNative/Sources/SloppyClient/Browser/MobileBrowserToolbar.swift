#if os(iOS)
import SwiftUI
import SloppyClientUI

@MainActor
struct MobileBrowserToolbar: View {
    let state: BrowserWorkspaceState
    let onNewTab: () -> Void
    let onTabs: () -> Void
    let onMenu: () -> Void
    let onAssistant: () -> Void
    var onTabSwipe: (BrowserTabSwipeDirection) -> Void = { _ in }
    var onTabSwipeChanged: ((CGSize) -> Void)?
    var onTabSwipeEnded: ((CGSize, CGSize) -> Void)?
    var onTabSwipeCancelled: () -> Void = {}
    var tabSwipe: MobileBrowserTabSwipe?
    var isCollapsed = false
    var onExpand: () -> Void = {}
    var onExpandedHeightChange: (CGFloat) -> Void = { _ in }
    @Namespace private var glassNamespace
    @GestureState private var isSwipingTabs = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if isCollapsed {
                compactControls
                    .highPriorityGesture(tabSwipeGesture)
            } else {
                expandedControls
                    .highPriorityGesture(tabSwipeGesture)
                    .glassEffectID(MobileBrowserAddressGlassID.active, in: glassNamespace)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onExpandedHeightChange($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isCollapsed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isCollapsed ? "browser-compact-toolbar" : "browser-mobile-toolbar")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityAction(named: Text("Previous tab")) { onTabSwipe(.previous) }
        .accessibilityAction(named: Text("Next tab")) { onTabSwipe(.next) }
        .onChange(of: isSwipingTabs) { _, dragging in
            guard !dragging else { return }
            Task { @MainActor in
                await Task.yield()
                if !isSwipingTabs { onTabSwipeCancelled() }
            }
        }
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($isSwipingTabs) { _, dragging, _ in dragging = true }
            .onChanged { value in onTabSwipeChanged?(value.translation) }
            .onEnded { value in
                if let onTabSwipeEnded {
                    onTabSwipeEnded(value.translation, value.predictedEndTranslation)
                    return
                }
                guard let direction = BrowserTabSwipeDirection.resolve(
                    horizontal: value.translation.width, vertical: value.translation.height
                ) else { return }
                onTabSwipe(direction)
            }
    }

    private var expandedControls: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                addressField
                assistantButton
                    .background(.quaternary.opacity(0.5), in: Circle())
            }
            navigationControls
        }
        .padding(8)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var addressField: some View {
        MobileBrowserAddressPager(state: state, swipe: tabSwipe, isCompact: false,
                                 onActivate: { state.presentSearch(newTab: state.selectedID == nil) },
                                 glassNamespace: glassNamespace)
    }

    private var navigationControls: some View {
        HStack(spacing: 0) {
            control("chevron.left", title: "Back", id: "browser-go-back") { state.selectedPage?.goBack() }
                .disabled(state.selectedPage?.canGoBack != true)
            Spacer(minLength: 0)
            control("chevron.right", title: "Forward", id: "browser-go-forward") { state.selectedPage?.goForward() }
                .disabled(state.selectedPage?.canGoForward != true)
            Spacer(minLength: 0)
            control("plus", title: "New tab", id: "browser-new-tab", action: onNewTab)
            Spacer(minLength: 0)
            Button(action: onTabs) {
                Text("\(state.tabs.count)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay { RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 1.5) }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tabs")
            .accessibilityValue("\(state.tabs.count) open \(state.tabs.count == 1 ? "tab" : "tabs")")
            .accessibilityIdentifier("browser-tabs-overview")
            Spacer(minLength: 0)
            control("ellipsis", title: "Browser menu", id: "browser-menu", action: onMenu)
        }
    }

    private var compactControls: some View {
        HStack(spacing: 10) {
            MobileBrowserAddressPager(state: state, swipe: tabSwipe, isCompact: true, onActivate: {
                onExpand()
                state.presentSearch(newTab: false)
            }, glassNamespace: glassNamespace)
            .accessibilityAction(named: Text("Show browser controls")) { onExpand() }
            assistantButton
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID("browser-assistant", in: glassNamespace)
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
    }

    private var assistantButton: some View {
        Button {
            onExpand()
            onAssistant()
        } label: {
            SloppyAssets.projectLogo
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("Assistant")
        .accessibilityIdentifier("browser-agent-toggle")
    }

    private func control(_ symbol: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}
#endif
