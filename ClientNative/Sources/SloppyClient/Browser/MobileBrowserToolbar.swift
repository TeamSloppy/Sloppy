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
    var isCollapsed = false
    var onExpand: () -> Void = {}
    var onExpandedHeightChange: (CGFloat) -> Void = { _ in }
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if isCollapsed {
                compactControls
            } else {
                expandedControls
                    .glassEffectID("browser-address", in: glassNamespace)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onExpandedHeightChange($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: isCollapsed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isCollapsed ? "browser-compact-toolbar" : "browser-mobile-toolbar")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
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
        HStack(spacing: 4) {
            Button { state.presentSearch(newTab: state.selectedID == nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: security.symbol).foregroundStyle(.secondary)
                    Text(state.selectedTab?.url?.host ?? "Search or enter address")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .padding(.leading, 12)
                .contentShape(Capsule())
            }
            .accessibilityLabel("Search or enter an address")
            .accessibilityValue("\(state.selectedTab?.url?.absoluteString ?? "Home"), \(security.label)")
            .accessibilityIdentifier("browser-address")
            if let page = state.selectedPage, state.selectedTab?.url != nil {
                control(page.isLoading ? "xmark" : "arrow.clockwise",
                        title: page.isLoading ? "Stop loading" : "Reload", id: "browser-reload") {
                    if page.isLoading { page.nativeWebView?.stopLoading() } else { page.reload() }
                }
            }
        }
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(alignment: .bottomLeading) {
            if let page = state.selectedPage, page.isLoading {
                ProgressView(value: min(1, max(0, page.estimatedProgress)))
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .accessibilityLabel("Loading page")
            }
        }
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
            Button {
                onExpand()
                state.presentSearch(newTab: false)
            } label: {
                Text(state.selectedTab?.url?.host ?? "Search or enter address")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 110, maxWidth: 210, minHeight: 44)
                    .padding(.horizontal, 16)
                    .contentShape(Capsule())
            }
            .accessibilityLabel("Search or enter an address")
            .accessibilityValue(state.selectedTab?.url?.absoluteString ?? "Home")
            .accessibilityIdentifier("browser-address")
            .accessibilityAction(named: Text("Show browser controls")) { onExpand() }
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectID("browser-address", in: glassNamespace)
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
                .frame(width: 24, height: 24)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("Assistant")
        .accessibilityIdentifier("browser-agent-toggle")
    }

    private var security: BrowserConnectionSecurity {
        state.selectedPage?.connectionSecurity(for: state.selectedTab?.url) ?? .empty
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
