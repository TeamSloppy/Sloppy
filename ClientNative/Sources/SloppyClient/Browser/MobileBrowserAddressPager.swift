#if os(iOS)
import SwiftUI
import SloppyClientUI

enum MobileBrowserAddressGlassID: Hashable, Sendable {
    case active
    case preview(MobileBrowserPageID)
}

/// The address pills share the page gesture, with a travel distance matching their own width.
@MainActor
struct MobileBrowserAddressPager: View {
    let state: BrowserWorkspaceState
    let swipe: MobileBrowserTabSwipe?
    let isCompact: Bool
    let onActivate: () -> Void
    let glassNamespace: Namespace.ID
    @Environment(\.theme) private var theme

    private var selectedPageID: MobileBrowserPageID { state.selectedID.map(MobileBrowserPageID.tab) ?? .home }
    private var sourcePageID: MobileBrowserPageID { swipe?.sourcePageID ?? selectedPageID }
    private var pageIDs: [MobileBrowserPageID] { swipe?.pageIDs ?? [selectedPageID] }

    var body: some View {
        sizingContent
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                GeometryReader { geometry in
                    GlassEffectContainer(spacing: 0) {
                        ZStack(alignment: .leading) {
                            ForEach(pageIDs, id: \.self) { pageID in
                                bubble(for: pageID)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .offset(x: swipe?.addressOffset(for: pageID, bubbleWidth: geometry.size.width) ?? 0)
                                    .allowsHitTesting(pageID == selectedPageID)
                                    .accessibilityHidden(pageID != selectedPageID)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .mask { Rectangle().padding(.vertical, -32) }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var sizingContent: some View {
        if isCompact {
            compactLabel(for: sourcePageID)
        } else {
            expandedBubble(for: sourcePageID)
        }
    }

    @ViewBuilder
    private func bubble(for pageID: MobileBrowserPageID) -> some View {
        if isCompact {
            Button(action: onActivate) { compactLabel(for: pageID) }
                .accessibilityLabel("Search or enter an address")
                .accessibilityValue(tab(for: pageID)?.url?.absoluteString ?? "Home")
                .accessibilityIdentifier("browser-address")
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID(pageID == sourcePageID ? MobileBrowserAddressGlassID.active : .preview(pageID), in: glassNamespace)
        } else {
            expandedBubble(for: pageID)
        }
    }

    private func compactLabel(for pageID: MobileBrowserPageID) -> some View {
        Text(tab(for: pageID)?.url?.host ?? "Search or enter address")
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minWidth: 110, maxWidth: 210, minHeight: 44)
            .padding(.horizontal, 16)
            .contentShape(Capsule())
    }

    private func expandedBubble(for pageID: MobileBrowserPageID) -> some View {
        let tab = tab(for: pageID)
        let page = page(for: pageID)
        let security = page?.connectionSecurity(for: tab?.url) ?? .empty
        return HStack(spacing: 4) {
            Button(action: onActivate) {
                HStack(spacing: 8) {
                    Image(systemName: security.symbol).foregroundStyle(.secondary)
                    Text(tab?.url?.host ?? "Search or enter address")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .padding(.leading, 12)
                .contentShape(Capsule())
            }
            .accessibilityLabel("Search or enter an address")
            .accessibilityValue("\(tab?.url?.absoluteString ?? "Home"), \(security.label)")
            .accessibilityIdentifier("browser-address")
            if let page, tab?.url != nil {
                Button {
                    if page.isLoading { page.nativeWebView?.stopLoading() } else { page.reload() }
                } label: {
                    Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 20))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(page.isLoading ? "Stop loading" : "Reload")
                .accessibilityIdentifier("browser-reload")
            }
        }
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(alignment: .bottomLeading) {
            if let page, page.isLoading {
                ProgressView(value: min(1, max(0, page.estimatedProgress)))
                    .progressViewStyle(.linear)
                    .tint(theme.colors.accent)
                    .padding(.horizontal, -16)
                    .accessibilityLabel("Loading page")
                    .allowsHitTesting(false)
            }
        }
        .mask(Capsule())
    }

    private func tab(for pageID: MobileBrowserPageID) -> BrowserTabRecord? {
        guard case .tab(let id) = pageID else { return nil }
        return state.tabs.first { $0.id == id }
    }

    private func page(for pageID: MobileBrowserPageID) -> WorkspaceWebViewModel? {
        guard case .tab(let id) = pageID else { return nil }
        return state.pages[id]
    }
}
#endif
