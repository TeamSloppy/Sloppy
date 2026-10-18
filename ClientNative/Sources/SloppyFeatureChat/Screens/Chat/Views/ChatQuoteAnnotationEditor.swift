#if os(macOS)
import SwiftUI
import SloppyClientUI

struct ChatQuoteAnnotationEditor: View {
    let quote: ChatComposerQuote
    let update: (String) -> Void
    let done: () -> Void
    @State private var comment: String
    @FocusState private var isFocused: Bool

    init(quote: ChatComposerQuote, update: @escaping (String) -> Void, done: @escaping () -> Void) {
        self.quote = quote
        self.update = update
        self.done = done
        _comment = State(initialValue: quote.comment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Annotation", systemImage: "quote.opening").font(.caption.weight(.semibold))
                Spacer()
                Button("Done", action: done).keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("chat.annotation.done")
            }
            Text(quote.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Divider()
            TextField("Add a comment…", text: $comment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .focused($isFocused)
                .accessibilityLabel("Annotation comment")
                .accessibilityIdentifier("chat.annotation.comment")
                .onChange(of: comment) { _, value in update(value) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { isFocused = true }
        .onExitCommand(perform: done)
    }
}

import AppKit
import Textual

@MainActor
final class ChatQuoteAnnotationPresenter: NSObject, NSPopoverDelegate {
    var anchors: [UUID: TextSelectionContext] = [:]
    private(set) var popover: NSPopover?
    private var onClose: (() -> Void)?

    @discardableResult
    func present(quote: ChatComposerQuote, context: TextSelectionContext,
                 update: @escaping (String) -> Void, finish: @escaping () -> Void) -> Bool {
        close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let scheme: ColorScheme = context.sourceView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        popover.contentViewController = NSHostingController(rootView:
            ChatQuoteAnnotationEditor(quote: quote, update: update, done: { [weak self] in self?.close() })
                .preferredColorScheme(scheme))
        self.popover = popover
        onClose = finish
        guard context.show(popover) else {
            self.popover = nil
            onClose = nil
            return false
        }
        return true
    }

    func close() { popover?.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        let finish = onClose
        onClose = nil
        popover = nil
        finish?()
    }
}

extension ChatScreenViewModel {
    func addAnchoredQuoteToComposer(_ context: TextSelectionContext, messageID: String, segmentIndex: Int) {
        quoteAnnotationPresenter.close()
        let quote = ChatComposerQuote(text: context.text, source: .init(
            messageID: messageID, segmentIndex: segmentIndex, location: context.location))
        if activeComposerDraftKey == nil { pendingComposerQuotes.append(quote) }
        composerQuotes.append(quote)
        saveActiveComposerDraft()
        editAnchoredComposerQuote(id: quote.id, context: context)
    }

    func editAnchoredComposerQuote(id: UUID, context: TextSelectionContext) {
        quoteAnnotationPresenter.anchors[id] = context
        _ = editComposerQuote(id: id)
    }

    @discardableResult
    func editComposerQuote(id: UUID) -> Bool {
        quoteAnnotationPresenter.close()
        guard let quote = composerQuotes.first(where: { $0.id == id }) else { return false }
        editingComposerQuoteID = id
        guard let context = quoteAnnotationPresenter.anchors[id] else { return false }
        return quoteAnnotationPresenter.present(quote: quote, context: context,
            update: { [weak self] in self?.updateComposerQuote(id: id, comment: $0) },
            finish: { [weak self] in self?.finishComposerQuoteEditing(id: id) })
    }
}
#endif
