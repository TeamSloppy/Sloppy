//
//  MainView+visionOS.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 05.07.2026.
//

import SwiftUI
import SloppyClientUI

#if os(visionOS)
@MainActor
struct VisionWorkspaceTabsOverview<PreviewContent: View>: View {
    let tabs: [WorkspaceTab]
    let selectedTabID: WorkspaceTab.ID?
    let onSelect: @MainActor (WorkspaceTab.ID) -> Void
    let onClose: @MainActor (WorkspaceTab.ID) -> Void
    let onCreate: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    @ViewBuilder let previewContent: (WorkspaceTab) -> PreviewContent

    @Environment(\.theme) private var theme

    private let columns = [
        GridItem(.flexible(minimum: 320, maximum: 700), spacing: 28),
        GridItem(.flexible(minimum: 320, maximum: 700), spacing: 28)
    ]

    var body: some View {
        VStack(spacing: theme.spacing.l) {
            overviewToolbar
                .padding(.top, theme.spacing.xxl)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(tabs) { tab in
                        VisionWorkspaceTabPreviewCard(
                            tab: tab,
                            isSelected: selectedTabID == tab.id,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab.id) },
                            preview: { previewContent(tab) }
                        )
                        .scrollTransition(
                            topLeading: .identity,
                            bottomTrailing: .interactive
                        ) { view, phase in
                            view
                                .opacity(phase.isIdentity ? 1 : 0)
                                .scaleEffect(phase.isIdentity ? 1 : 0.75)
                                .blur(radius: phase.isIdentity ? 0 : 10)
                        }
                        .visualEffect3D { effect, proxy in
                            effect
                                .rotationEffect(.degrees(4))
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.xxl)
                .padding(.bottom, theme.spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var overviewToolbar: some View {
        HStack(spacing: theme.spacing.s) {
            Text("\(tabs.count) Tabs")
                .font(.system(size: theme.typography.body, weight: .semibold))
                .padding(.horizontal, 32)

            Button(action: onCreate) {
                Label("New tab", systemImage: "plus")
                    .font(.system(size: theme.typography.body, weight: .semibold))
                    .padding()
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.system(size: theme.typography.body, weight: .semibold))
                    .padding()
            }
        }
        .buttonStyle(VisionFloatingTabBarButtonStyle(in: .capsule))
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.s)
        .glassBackgroundEffect()
    }
}

@MainActor
private struct VisionWorkspaceTabPreviewCard<Preview: View>: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    @ViewBuilder let preview: () -> Preview

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    preview()
                        .scaleEffect(0.42, anchor: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .frame(height: 320, alignment: .topLeading)
                        .mask(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                        )

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: theme.typography.caption, weight: .bold))
                            .foregroundColor(theme.colors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.22 as CGFloat)))
                    }
                    .buttonStyle(.plain)
                    .padding(theme.spacing.m)
                }

                HStack {
                    Text(tab.title)
                        .font(.system(size: theme.typography.body, weight: .semibold))
                        .foregroundColor(theme.colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: theme.spacing.s)

                    Text(tab.kind.rawValue)
                        .font(.system(size: theme.typography.caption))
                        .foregroundColor(theme.colors.textSecondary)
                }
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.m)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(theme.colors.surfaceRaised.opacity(isSelected ? 0.68 as CGFloat : 0.42 as CGFloat))
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(
                                isSelected
                                ? Color.white.opacity(0.32 as CGFloat)
                                : Color.white.opacity(0.12 as CGFloat),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VisionWorkspaceTabsOverview(
        tabs: [
            .init(
                key: .chatSession(""),
                kind: .chat,
                title: "",
                payload: .chatSession(sessionID: "", title: "")
            )
        ],
        selectedTabID: nil,
        onSelect: {_ in },
        onClose: { _ in },
        onCreate: {},
        onDismiss: {},
        previewContent: { _ in }
    )
}
#endif
