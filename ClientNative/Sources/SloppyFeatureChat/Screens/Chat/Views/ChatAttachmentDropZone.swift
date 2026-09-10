import SwiftUI
import UniformTypeIdentifiers
import SloppyClientUI

/// Shared by the transcript surface and independently hosted composers.
@MainActor
struct ChatAttachmentDropZone: ViewModifier {
    let viewModel: ChatScreenViewModel
    @Environment(\.theme) private var theme
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .data, .url], isTargeted: $isTargeted) { providers in
                viewModel.attachItemProviders(providers)
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(theme.colors.background.opacity(0.9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(theme.colors.accentCyan, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        }
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                    .font(.title)
                                Text("Drop to attach")
                                    .font(.headline)
                            }
                            .foregroundStyle(theme.colors.accentCyan)
                        }
                        .padding(12)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Drop resources to attach to this chat")
                }
            }
    }
}
