import SwiftUI
import SloppyClientUI

struct ChatSentAnnotationsBubble: View {
    let annotations: [ChatSentAnnotations.Annotation]
    @Environment(\.theme) private var theme
    @State private var isPresented = false
    @State private var isPinned = false
    @State private var isHoveringButton = false
    @State private var isHoveringPopover = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button {
            isPinned.toggle()
            isPresented = isPinned
        } label: {
            Label(annotations.count == 1 ? "1 annotation" : "\(annotations.count) annotations", systemImage: "text.bubble")
                .font(.system(size: theme.typography.caption, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(theme.colors.textSecondary)
                .background(theme.colors.surfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(theme.colors.border, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.user-message.annotations")
        .accessibilityHint("Show the selected text and user comments")
        .onHover { hovering in
            isHoveringButton = hovering
            updateHover()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            details
                .onHover { hovering in
                    isHoveringPopover = hovering
                    updateHover()
                }
                .onDisappear {
                    isPinned = false
                    isHoveringPopover = false
                }
                .presentationCompactAdaptation(.popover)
        }
        .onDisappear { dismissTask?.cancel() }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(annotations.enumerated()), id: \.offset) { index, annotation in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .foregroundStyle(theme.colors.textSecondary)
                        VStack(alignment: .leading, spacing: 10) {
                            detail("Selected text:", text: annotation.selectedText)
                                .accessibilityIdentifier("chat.user-message.annotation.\(index).selection")
                            if !annotation.comment.isEmpty {
                                detail("User comment:", text: annotation.comment)
                                    .accessibilityIdentifier("chat.user-message.annotation.\(index).comment")
                            }
                            if let source = annotation.source {
                                detail("Source:", text: source)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: theme.typography.body))
        .foregroundStyle(theme.colors.textPrimary)
        .textSelection(.enabled)
        .frame(idealWidth: 420, maxWidth: 480, maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("chat.user-message.annotations.details")
    }

    private func detail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(theme.colors.textSecondary)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func updateHover() {
        dismissTask?.cancel()
        if isHoveringButton || isHoveringPopover {
            isPresented = true
        } else if !isPinned {
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, !isPinned, !isHoveringButton, !isHoveringPopover else { return }
                isPresented = false
            }
        }
    }
}
