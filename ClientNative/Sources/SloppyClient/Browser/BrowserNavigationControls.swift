import SwiftUI
import SloppyClientUI

@MainActor
struct BrowserNavigationControls: View {
    let state: BrowserWorkspaceState
    @Environment(\.theme) private var theme
#if os(macOS)
    private let addressHeight: CGFloat = 36
    private let addressCornerRadius: CGFloat = 16
    @State private var isAddressHovered = false
    @FocusState private var isExtensionsFocused: Bool
#else
    private let addressHeight: CGFloat = 44
    private let addressCornerRadius: CGFloat = 8
#endif

    var body: some View {
        VStack(spacing: 6) {
#if !os(macOS)
            HStack(spacing: 4) {
                BrowserNavigationButtons(state: state, group: .history)
                Spacer(minLength: 0)
                BrowserNavigationButtons(state: state, group: .page)
            }
#endif
            addressField
            .overlay(alignment: .bottomLeading) {
                if let page = state.selectedPage, page.isLoading {
                    GeometryReader { geometry in
                        Rectangle().fill(theme.colors.accent.opacity(0.8))
                            .frame(width: geometry.size.width * loadingProgress, height: 2)
                    }
                    .frame(height: 2)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: addressCornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.16), value: state.selectedPage?.isLoading)
            .animation(.easeOut(duration: 0.18), value: state.selectedPage?.estimatedProgress)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-address-bar")
    }

    @ViewBuilder
    private var addressField: some View {
#if os(macOS)
        HStack(spacing: 6) {
            BrowserConnectionSecurityButton(page: state.selectedPage, requestedURL: state.selectedTab?.url)
            Button { state.presentSearch(newTab: false) } label: {
                Text(state.selectedTab?.url?.host ?? "Search or enter an address")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: addressHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Search or enter an address")
            .accessibilityValue(addressAccessibilityValue)
            .accessibilityIdentifier("browser-address")
            BrowserExtensionsMenu(state: state)
                .focused($isExtensionsFocused)
                .opacity(isAddressHovered || isExtensionsFocused ? Double(1) : Double(0))
                .allowsHitTesting(isAddressHovered || isExtensionsFocused)
            HStack(spacing: 4) {
                BrowserNavigationButtons(state: state, group: .page, compact: true, showsBookmark: isAddressHovered)
            }
            .fixedSize()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: addressHeight)
        .background {
            RoundedRectangle(cornerRadius: addressCornerRadius, style: .continuous).fill(theme.colors.surfaceRaised)
        }
        .contentShape(RoundedRectangle(cornerRadius: addressCornerRadius, style: .continuous))
        .onHover { isAddressHovered = $0 }
#else
        Button { state.presentSearch(newTab: false) } label: {
            HStack(spacing: 8) {
                Image(systemName: connectionSecurity.symbol).foregroundStyle(.secondary)
                    .help(connectionSecurity.label)
                Text(state.selectedTab?.url?.host ?? "Search or enter an address").lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: addressHeight)
            .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: addressCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: addressCornerRadius, style: .continuous))
        }
        .accessibilityLabel("Search or enter an address")
        .accessibilityValue(addressAccessibilityValue)
        .accessibilityIdentifier("browser-address")
#endif
    }

    private var connectionSecurity: BrowserConnectionSecurity {
        state.selectedPage?.connectionSecurity(for: state.selectedTab?.url) ?? .empty
    }

    private var addressAccessibilityValue: String {
        let address = state.selectedTab?.url?.absoluteString ?? "Home"
        return state.selectedPage?.isLoading == true ? "\(address), Loading \(Int(loadingProgress * 100))%" : "\(address), \(connectionSecurity.label)"
    }

    private var loadingProgress: Double {
        let value = state.selectedPage?.estimatedProgress ?? 0
        return value.isFinite ? min(1, max(0, value)) : 0
    }
}

@MainActor
struct BrowserNavigationButtons: View {
    enum ButtonGroup { case history, page }

    let state: BrowserWorkspaceState
    let group: ButtonGroup
    var compact = false
    var showsBookmark = true
    @FocusState private var isBookmarkFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        switch group {
        case .history: navigationButtons
        case .page: pageButtons
        }
    }

    private var navigationButtons: some View {
        Group {
            control("chevron.left", title: "Back", enabled: state.selectedPage?.canGoBack == true) { state.selectedPage?.goBack() }
                .accessibilityIdentifier("browser-go-back")
            control("chevron.right", title: "Forward", enabled: state.selectedPage?.canGoForward == true) { state.selectedPage?.goForward() }
                .accessibilityIdentifier("browser-go-forward")
#if !os(macOS)
            reloadButton
#endif
        }
    }

    @ViewBuilder
    private var pageButtons: some View {
        if let tab = state.selectedTab, let url = tab.url {
            control(state.library.isBookmarked(url) ? "bookmark.fill" : "bookmark", title: "Bookmark page") {
                state.library.toggleBookmark(url: url, title: tab.title)
            }
            .accessibilityIdentifier("browser-bookmark-page")
#if os(macOS)
            .focused($isBookmarkFocused)
            .opacity(showsBookmark || isBookmarkFocused ? Double(1) : Double(0))
            .allowsHitTesting(showsBookmark || isBookmarkFocused)
#endif
#if os(macOS)
            reloadButton
#else
            control("xmark", title: "Close tab") { state.close(tab.id) }
                .accessibilityIdentifier("browser-close-tab")
#endif
        }
    }

    private var reloadButton: some View {
        control("arrow.clockwise", title: "Reload", enabled: state.selectedPage != nil) { state.selectedPage?.reload() }
            .accessibilityIdentifier("browser-reload")
    }

    private var controlSize: CGFloat {
#if os(macOS)
        compact ? 22 : 30
#else
        44
#endif
    }

    private func control(_ symbol: String, title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: controlSize, height: controlSize).contentShape(Rectangle())
        }
        .disabled(!enabled)
        .foregroundStyle(enabled ? theme.colors.textSecondary : theme.colors.textMuted.opacity(0.4))
        .accessibilityLabel(title)
        .help(title)
    }
}
