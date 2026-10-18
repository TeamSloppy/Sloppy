import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif


struct MobileComposerCircleButton: View {
    let symbol: MaterialSymbol
    var foregroundColor: Color = Theme.sloppyDark.colors.textPrimary
    var fillColor: Color = Color.fromHex(0x1C1C1E).opacity(0.96 as CGFloat)
    let action: @MainActor () -> Void
    
    @Environment(\.theme) private var theme

    var body: some View {
        #if os(macOS)
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(foregroundColor)
                .frame(
                    width: ChatComposerView.buttonSize,
                    height: ChatComposerView.buttonSize
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .backportGlassEffect(.regular.interactive(), in: .circle)
        .padding(.bottom, (ChatComposerView.panelHeight - ChatComposerView.buttonSize) / 2)
        #else
        Button(action: action) {
            Icons.symbol(symbol, size: 18)
                .foregroundColor(foregroundColor)
                .frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)
                .background(theme.colors.textPrimary.opacity(0.10 as CGFloat), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonBorderShape(.circle)
#if os(visionOS)
        .glassBackgroundEffect()
#else
        .buttonStyle(.plain)
#endif
        #endif
    }
}

struct ComposerAddMenu: View {
    let viewModel: ChatScreenViewModel
    let supportsReasoningEffort: Bool

    var tabActions: ChatComposerTabActions? = nil
    @Environment(\.theme) private var theme
    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        Menu {
            if let tabActions {
                Section("Chats") {
                    Button("Show chats", systemImage: "square.stack", action: tabActions.showOverview)
                    Button("New chat", systemImage: "square.and.pencil", action: tabActions.createTab)
                }
            }
            Section("Voice") {
                Button { viewModel.toggleReadAloud() } label: {
                    Label(
                        viewModel.isReadAloudEnabled ? "Read replies aloud ✓" : "Read replies aloud",
                        systemImage: "speaker.wave.2"
                    )
                }
                .accessibilityIdentifier("chat.voice.read-aloud")
                if viewModel.isSpeakingReply {
                    Button("Stop speaking", systemImage: "speaker.slash") { viewModel.stopSpeakingReply() }
                }
            }
            Section("Chat") {
                Button { viewModel.openLongChat() } label: {
                    Label(viewModel.isLongChat ? "Conversation ✓" : "Open conversation", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("chat.long-chat.open")
                Button { viewModel.pickNewSession() } label: {
                    Label("New separate chat", systemImage: "square.and.pencil")
                }
                if viewModel.isLongChat && viewModel.activeLongChatTaskCount > 0 {
                    Button("Stop all tasks", role: .destructive) { viewModel.stopLongChatTasks() }
                        .accessibilityIdentifier("chat.long-chat.stop-tasks")
                }
            }

#if os(macOS)
            Button {
                viewModel.isAttachmentPickerShown = true
            } label: {
                Label("Files and Attach", systemImage: "paperclip")
            }

            Button {
                DispatchQueue.main.async {
                    viewModel.insertCodeBlock()
                }
            } label: {
                Label("Code block", systemImage: "chevron.left.forwardslash.chevron.right")
            }
#else
            Button {
                viewModel.isCameraPickerShown = true
            } label: {
                Label("Camera", systemImage: "camera")
            }
#if os(visionOS)
            .disabled(true)
#endif

            Button {
                viewModel.isPhotoPickerShown = true
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
            }

            Button {
                viewModel.isAttachmentPickerShown = true
            } label: {
                Label("Files", systemImage: "folder")
            }

            if idiom != .phone {
                agentMenu
                effortMenu
            }
#endif
        } label: {
#if os(macOS)
            Color.clear
                .frame(
                    width: ChatComposerView.buttonSize,
                    height: ChatComposerView.buttonSize
                )
#else
            Icons.symbol(.add, size: 18)
                .foregroundColor(theme.colors.textSecondary)
                .frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)
                .background(theme.colors.textPrimary.opacity(0.10 as CGFloat), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
#endif
        }
#if os(macOS)
        .menuStyle(CustomMenuButtonStyle())
#elseif os(visionOS)
        .menuIndicator(.hidden)
        .buttonBorderShape(.circle)
        .glassBackgroundEffect()
#else
        .menuIndicator(.hidden)
        .buttonBorderShape(.circle)
        .buttonStyle(.plain)
#endif
        .accessibilityLabel("Add")
    }

    private var agentMenu: some View {
        Menu {
            if viewModel.agents.isEmpty {
                Text("No agents")
            } else {
                ForEach(viewModel.agents) { agent in
                    Button {
                        viewModel.pickAgent(agent)
                    } label: {
                        ComposerMenuItem(
                            title: agent.displayName,
                            isSelected: viewModel.selectedAgent?.id == agent.id
                        )
                    }
                }
            }
        } label: {
            Label("Agent", systemImage: "person")
        }
    }

    private var effortMenu: some View {
        Menu {
            ForEach(ChatReasoningEffort.allCases) { effort in
                Button {
                    viewModel.pickReasoningEffort(effort)
                } label: {
                    ComposerMenuItem(
                        title: effort.title,
                        isSelected: viewModel.selectedReasoningEffort == effort
                    )
                }
            }
        } label: {
            Label("Effort", systemImage: "gauge.with.dots.needle.50percent")
        }
        .disabled(!supportsReasoningEffort)
    }
}

struct ChatComposerCapsuleChrome: View {
    let height: CGFloat
    let aspectRatio: CGFloat
    let accentColor: Color

    @Environment(\.theme) private var theme

    var body: some View {
        Capsule()
            #if os(iOS)
            .fill(theme.colors.background)
            #else
            .fill(Color.black)
            #endif
    }
}

struct SubmitButton: ButtonStyle {

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private static let sendSize: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        let actionFill = Color.accentColor

        configuration.label
            .foregroundColor(theme.colors.textPrimary)
            .frame(width: Self.sendSize, height: Self.sendSize)
            .padding(4)
            .backportGlassEffect(
                .regular.tint(actionFill.opacity(isEnabled ? 1 : 0.4)),
                in: Circle()
            )
    }
}

struct CustomMenuButtonStyle: MenuStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Menu(configuration)
                .frame(
                    width: 36,
                    height: 36
                )
                .contentShape(.circle)
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)

            Icons.symbol(.add, size: theme.typography.heading)
                .foregroundColor(theme.colors.textPrimary)
                .allowsHitTesting(false)
        }
        .frame(
            width: 36,
            height: 36
        )
        .buttonBorderShape(.circle)
        .buttonSizing(.flexible)
        .background(theme.colors.surfaceRaised, in: Circle())
    }
}
