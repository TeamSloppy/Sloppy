//
//  DesktopWorkspaceTabButton.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 11.07.2026.
//

import SwiftUI
import SloppyClientCore
import SloppyClientUI

@MainActor
struct DesktopWorkspaceTabButton: View {
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
        Button(action: onSelect) {
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
