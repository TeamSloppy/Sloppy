#if os(macOS)
import Foundation
import SwiftUI
import SloppyClientUI

@MainActor
struct BrowserSplitWorkspaceView<PageContent: View>: View {
    let state: BrowserWorkspaceState
    let split: BrowserSplitGroup
    @ViewBuilder let pageContent: (BrowserTabRecord) -> PageContent
    @Environment(\.theme) private var theme

    private var tabs: [BrowserTabRecord] { state.visibleTabs }
    private var columns: Int { tabs.count <= 3 ? max(1, tabs.count) : Int(ceil(sqrt(Double(tabs.count)))) }

    var body: some View {
        VSplitView {
            ForEach(0..<((tabs.count + columns - 1) / columns), id: \.self) { row in
                HSplitView {
                    ForEach(Array(tabs.dropFirst(row * columns).prefix(columns))) { tab in
                        pane(tab)
                    }
                }
            }
        }
        .id(split.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-split-view")
    }

    private func pane(_ tab: BrowserTabRecord) -> some View {
        VStack(spacing: 0) {
            Button { state.select(tab.id) } label: {
                HStack(spacing: 8) {
                    Text(tab.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if state.selectedID == tab.id {
                        Image(systemName: "circle.fill").font(.system(size: 5))
                    }
                }
                .font(.system(size: 12, weight: state.selectedID == tab.id ? .semibold : .regular))
                .foregroundStyle(state.selectedID == tab.id ? theme.colors.textPrimary : theme.colors.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(theme.colors.surfaceRaised)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Activate pane: \(tab.title)")
            .accessibilityIdentifier("browser-split-activate-\(tab.id)")
            Divider()
            pageContent(tab)
        }
        .frame(minWidth: 140, minHeight: 140)
        .clipped()
        .overlay {
            Rectangle()
                .strokeBorder(state.selectedID == tab.id ? theme.colors.textMuted : theme.colors.border,
                              lineWidth: state.selectedID == tab.id ? 2 : 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-split-pane-\(tab.id)")
    }
}
#endif
