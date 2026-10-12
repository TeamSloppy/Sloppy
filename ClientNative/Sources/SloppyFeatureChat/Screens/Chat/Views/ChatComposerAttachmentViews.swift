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


struct ChatComposerAttachmentStrip: View {
    let attachments: [ChatComposerAttachment]
    let annotate: @MainActor (ChatComposerAttachment) -> Void
    let remove: @MainActor (ChatComposerAttachment.ID) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, theme.spacing.xs)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Attachments")
    }

    private func attachmentChip(_ attachment: ChatComposerAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                annotate(attachment)
            } label: {
                ChatComposerAttachmentPreview(attachment: attachment)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.colors.border, lineWidth: theme.borders.thin)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !attachment.annotations.isEmpty {
                            Text("\(attachment.annotations.count)")
                                .font(.caption.bold())
                                .foregroundStyle(ChatAnnotationStyle.ink)
                                .padding(6)
                                .background(ChatAnnotationStyle.mint, in: Circle())
                                .padding(6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!attachment.mimeType.hasPrefix("image/"))
            .accessibilityLabel("Annotate \(attachment.name)")
            .accessibilityIdentifier("chat.composer.attachment.\(attachment.id).annotate")

            Button {
                remove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        theme.colors.textPrimary,
                        theme.colors.surfaceRaised
                    )
            }
            .buttonStyle(.plain)
            .padding(5)
            .accessibilityLabel("Remove \(attachment.name)")
        }
    }
}

struct ChatComposerAttachmentPreview: View {
    let attachment: ChatComposerAttachment

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let image = platformImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: theme.spacing.xs) {
                    Image(systemName: "doc")
                        .font(.system(size: 26))
                        .foregroundColor(theme.colors.accentCyan)
                    Text(attachment.name)
                        .font(.system(size: theme.typography.micro, weight: .medium))
                        .foregroundColor(theme.colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(attachment.sizeBytes),
                            countStyle: .file
                        )
                    )
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(theme.colors.textMuted)
                }
                .padding(theme.spacing.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.surfaceRaised.opacity(0.96))
            }
        }
        .accessibilityLabel(attachment.name)
    }

    private var platformImage: Image? {
        guard attachment.mimeType.hasPrefix("image/") else {
            return nil
        }

        #if os(macOS)
        guard let image = NSImage(data: attachment.data) else {
            return nil
        }
        return Image(nsImage: image)
        #elseif canImport(UIKit)
        guard let image = UIImage(data: attachment.data) else {
            return nil
        }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}
