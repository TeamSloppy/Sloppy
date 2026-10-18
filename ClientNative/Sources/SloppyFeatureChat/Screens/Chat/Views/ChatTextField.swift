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


struct ComposerMenuItem: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

struct ChatTextField: View {
    @Bindable var draft: ChatComposerDraft
    let submit: @MainActor () -> Void
    var onFocusChanged: @MainActor (Bool) -> Void = { _ in }

    @Environment(\.allowsAutomaticComposerFocus) private var allowsAutomaticComposerFocus
    @State private var isTextFieldFocused = false
    @State private var composerCursorOffset: Int?
    @State private var editorHeight = Constants.editorMinimumHeight
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    @Environment(\.chatComposerReferenceOpenHandler) private var referenceOpenHandler
    @Environment(ChatScreenViewModel.self) private var viewModel

    private var agentDisplayName: String {
        return viewModel.selectedAgent?.displayName ?? "Sloppy"
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary

        return nativeTextEditor(
            fontSize: idiom == .phone ? 17 : ty.body,
            primaryColor: fieldInk,
            placeholderColor: c.textMuted,
            commandColor: c.accentCyan,
            mentionColor: c.accent,
            tagColor: c.accentAcid
        )
            .frame(height: editorHeight)
#if os(macOS)
            .padding(.horizontal, 0)
#else
            .padding(.horizontal, idiom == .phone ? 0 : Constants.fieldHorizontalPadding)
#endif
            .padding(.vertical, sp.s)
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Constants.fieldHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .pointerStyle(.horizontalText)
            #endif
            .clipped()
            .layoutPriority(1)
            .onChange(of: viewModel.composerFocusResetToken) { _, _ in
                isTextFieldFocused = false
            }
            .task(id: viewModel.composerFocusRequestToken) {
                guard allowsAutomaticComposerFocus, viewModel.composerFocusRequestToken > 0 else {
                    return
                }
                await Task.yield()
                isTextFieldFocused = true
            }
            .onChange(of: isTextFieldFocused) { _, isFocused in
                onFocusChanged(isFocused)
            }
            .onChange(of: draft.text) { oldValue, newValue in
                let cursorOffset = composerCursorOffset
                    ?? ChatComposerTextEdit.cursorOffsetAfterEdit(
                        from: oldValue,
                        to: newValue
                    )
                composerCursorOffset = nil
                viewModel.updateComposerSuggestions(
                    for: newValue,
                    cursorOffset: cursorOffset
                )
            }
    }

    @ViewBuilder
    private func nativeTextEditor(
        fontSize: CGFloat,
        primaryColor: Color,
        placeholderColor: Color,
        commandColor: Color,
        mentionColor: Color,
        tagColor: Color
    ) -> some View {
        #if os(macOS)
        AppKitChatComposerTextEditor(
            text: $draft.text,
            selection: $draft.selection,
            isFocused: $isTextFieldFocused,
            measuredHeight: $editorHeight,
            placeholder: "Ask \(agentDisplayName) or type / for commands",
            fontSize: fontSize,
            primaryColor: primaryColor,
            placeholderColor: placeholderColor,
            commandColor: commandColor,
            mentionColor: mentionColor,
            tagColor: tagColor,
            codeBackgroundColor: theme.colors.accentCyan.opacity(0.12),
            maximumVisibleLines: Constants.maximumVisibleLines,
            textContainerInset: CGSize(
                width: Constants.editorContentHorizontalInset,
                height: Constants.editorContentVerticalInset
            ),
            lineFragmentPadding: Constants.editorNativeTextContainerInset,
            cursorOffsetChanged: { composerCursorOffset = $0 },
            moveSuggestionSelection: viewModel.moveComposerSuggestionSelection,
            applySelectedSuggestion: viewModel.applySelectedComposerSuggestion,
            submit: submit,
            pasteAttachment: pasteAttachmentsFromSystemPasteboard,
            references: draft.references,
            openReference: { reference in referenceOpenHandler?(reference, viewModel) },
            registerReferences: viewModel.registerComposerReferences
        )
        #else
        UIKitChatComposerTextEditor(
            text: $draft.text,
            selection: $draft.selection,
            isFocused: $isTextFieldFocused,
            measuredHeight: $editorHeight,
            placeholder: idiom == .phone ? "Plan, ask, build…" : "Ask \(agentDisplayName)",
            fontSize: fontSize,
            primaryColor: primaryColor,
            placeholderColor: placeholderColor,
            commandColor: commandColor,
            mentionColor: mentionColor,
            tagColor: tagColor,
            maximumVisibleLines: Constants.maximumVisibleLines,
            textContainerInset: EdgeInsets(
                top: Constants.editorContentVerticalInset,
                leading: idiom == .phone ? 0 : Constants.editorContentHorizontalInset,
                bottom: Constants.editorContentVerticalInset,
                trailing: idiom == .phone ? 0 : Constants.editorContentHorizontalInset
            ),
            lineFragmentPadding: Constants.editorNativeTextContainerInset,
            cursorOffsetChanged: { composerCursorOffset = $0 },
            moveSuggestionSelection: viewModel.moveComposerSuggestionSelection,
            applySelectedSuggestion: viewModel.applySelectedComposerSuggestion,
            submit: submit,
            pasteItemProviders: viewModel.attachItemProviders
        )
        #endif
    }

    #if os(macOS)
    private func pasteAttachmentsFromSystemPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        let fileObjects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let fileURLs = fileObjects.compactMap {
            ($0 as? NSURL)?.filePathURL
        }

        if !fileURLs.isEmpty {
            viewModel.attachFileURLs(fileURLs)
            return true
        }

        if let pngData = pasteboard.data(forType: .png) {
            viewModel.attachData(
                pngData,
                suggestedName: "Pasted Image.png",
                mimeType: "image/png"
            )
            return true
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return pasteGenericAttachment(from: pasteboard)
        }

        viewModel.attachData(
            pngData,
            suggestedName: "Pasted Image.png",
            mimeType: "image/png"
        )
        return true
    }

    private func pasteGenericAttachment(from pasteboard: NSPasteboard) -> Bool {
        guard let pasteboardType = pasteboard.types?.first(where: { pasteboardType in
            guard let contentType = UTType(pasteboardType.rawValue) else { return false }
            return ChatComposerPasteboard.isAttachmentType(contentType)
        }),
        let data = pasteboard.data(forType: pasteboardType),
        let contentType = UTType(pasteboardType.rawValue) else {
            return false
        }

        let fileExtension = contentType.preferredFilenameExtension ?? "bin"
        viewModel.attachData(
            data,
            suggestedName: "Pasted Attachment.\(fileExtension)",
            mimeType: contentType.preferredMIMEType ?? "application/octet-stream"
        )
        return true
    }
    #endif
}
