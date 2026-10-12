import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import UniformTypeIdentifiers
#if canImport(PhotosUI) && !os(macOS)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
struct ChatContextToolbarModifier: ViewModifier {
    let viewModel: ChatScreenViewModel
    let isEnabled: Bool

    @Environment(\.userInterfaceIdiom) private var idiom

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        if idiom == .phone {
            content
        } else if isEnabled {
            content.toolbar(id: "agent.settings") {
                ToolbarItem(id: "agent", placement: .secondaryAction) {
                    ChatAgentToolbarMenu(
                        selectedAgent: viewModel.selectedAgent,
                        agents: viewModel.agents,
                        onSelectAgent: viewModel.pickAgent
                    )
                }
                ToolbarItem(id: "model", placement: .secondaryAction) {
                    ChatModelToolbarMenu(
                        selectedModelId: viewModel.selectedModelId,
                        models: viewModel.availableModels,
                        onSelectModel: viewModel.pickModel
                    )
                }
            }
        } else {
            content
        }
        #endif
    }
}

@MainActor
struct ChatNavigationToolbarModifier: ViewModifier {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?
    let isEnabled: Bool

    @Environment(\.userInterfaceIdiom) private var idiom

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
#if os(iOS)
            if idiom == .phone {
                content
                    .navigationTitle(viewModel.activeSessionTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Rename Chat", systemImage: "pencil") { viewModel.requestRenameActiveSession() }
                                .disabled(viewModel.selectedSessionId == nil)
                                .accessibilityIdentifier("chat.navigation.rename")
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.startNewMessage()
                            } label: {
                                Label("New message", systemImage: "square.and.pencil")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel("New message")
                            .accessibilityIdentifier("chat.navigation.new-message")
                            .disabled(viewModel.selectedAgent == nil && viewModel.agents.isEmpty)
                        }
                    }
            } else {
                desktopToolbar(content)
            }
#else
            desktopToolbar(content)
#endif
        } else {
            content
        }
    }

    private func desktopToolbar(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigation) {
                ChatNavigationLeadingItems(
                    viewModel: viewModel,
                    onOpenSidebar: onOpenSidebar
                )
            }
        }
    }
}

@MainActor
struct ChatNavigationLeadingItems: View {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72 as CGFloat))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    Icons.symbol(.menu, size: 15)
                        .foregroundColor(.white.opacity(0.72 as CGFloat))
                        .frame(width: 30, height: 30)
                }
            }

            if let activeContextTitle = viewModel.activeContextTitle {
                Text(activeContextTitle)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7 as CGFloat))
                    .lineLimit(1)
            }
        }
    }
}
