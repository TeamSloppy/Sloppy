import SloppyClientCore
import SwiftUI

@MainActor
struct CanvasWorkspaceInspector: View {
    let viewModel: CanvasWorkspaceViewModel
    @Binding var prompt: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Agent Session", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isInspectorPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Inspector")
            }
            .padding(14)

            Divider()

            chat
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .accessibilityIdentifier("canvas-workspace-inspector")
    }

    private var visibleMessages: [ChatMessage] {
        viewModel.messages.filter { message in
            message.role != .system
                && (!message.textContent.isEmpty || message.id == viewModel.streamingMessageID)
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if visibleMessages.isEmpty {
                            ContentUnavailableView(
                                "No Agent Session",
                                systemImage: "sparkles",
                                description: Text("Ask an agent to build or edit this workspace.")
                            )
                            .padding(.top, 40)
                        }
                        ForEach(visibleMessages) { message in
                            CanvasWorkspaceChatBubble(
                                message: message,
                                isStreaming: message.id == viewModel.streamingMessageID
                            )
                            .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: viewModel.chatScrollToken) {
                    if let id = visibleMessages.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message agent…", text: $prompt, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSendingPrompt)
            }
            .padding(12)
        }
    }

    private func send() {
        let content = prompt
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        prompt = ""
        Task { await viewModel.sendPrompt(content) }
    }
}

@MainActor
struct CanvasWorkspaceLayersPanel: View {
    let viewModel: CanvasWorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Layers", systemImage: "square.3.layers.3d")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isLayersPanelPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Layers")
            }
            .padding(14)

            Divider()

            layers
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .accessibilityIdentifier("canvas-workspace-layers-panel")
    }

    private var layers: some View {
        List(selection: Binding(
            get: { viewModel.selectedElementID },
            set: { viewModel.selectedElementID = $0 }
        )) {
            ForEach((viewModel.document?.elements ?? []).filter { $0.id != "native-pencil-drawing" }.sorted { $0.zIndex > $1.zIndex }) { element in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(element.title).lineLimit(1)
                        Text(element.kind.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon(for: element.kind))
                        .foregroundStyle(.secondary)
                }
                .tag(element.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if viewModel.document?.elements.filter({ $0.id != "native-pencil-drawing" }).isEmpty != false {
                ContentUnavailableView("No Layers", systemImage: "square.3.layers.3d", description: Text("Add something to the canvas."))
            }
        }
    }

    private func icon(for kind: CanvasWorkspaceElementKind) -> String {
        switch kind {
        case .sticky: "note.text"
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .image: "photo"
        case .table: "tablecells"
        case .frame: "rectangle.dashed"
        case .widget: "safari"
        }
    }
}

private struct CanvasWorkspaceChatBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 28) }
            HStack(spacing: 7) {
                if isStreaming && message.textContent.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(message.textContent.isEmpty ? "Working…" : message.textContent)
            }
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role != .user { Spacer(minLength: 28) }
        }
    }
}
