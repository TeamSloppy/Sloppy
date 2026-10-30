import Foundation
import SwiftUI
import SloppyClientCore
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif


#if os(macOS)
struct AppKitChatComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat

    let placeholder: String
    let fontSize: CGFloat
    let primaryColor: Color
    let placeholderColor: Color
    let commandColor: Color
    let mentionColor: Color
    let tagColor: Color
    let codeBackgroundColor: Color
    let maximumVisibleLines: Int
    let textContainerInset: CGSize
    let lineFragmentPadding: CGFloat
    let cursorOffsetChanged: @MainActor (Int?) -> Void
    let moveSuggestionSelection: @MainActor (ChatComposerSuggestionSelectionDirection) -> Bool
    let applySelectedSuggestion: @MainActor () -> Bool
    let submit: @MainActor () -> Void
    let pasteAttachment: @MainActor () -> Bool
    var references: [ChatComposerReference] = []
    var openReference: (@MainActor (ChatComposerReference) -> Void)? = nil
    var registerReferences: @MainActor ([ChatComposerReference]) -> Void = { _ in }
    var onCommittedText: (@MainActor (String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ComposerNSScrollView {
        let scrollView = ComposerNSScrollView()
        let textView = Self.makeTextView()
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.onFocusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.isFocused = focused
        }
        scrollView.documentView = textView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateHeight()
            if coordinator?.parent.isFocused == true { coordinator?.synchronizeFocus() }
        }
        textView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateHeight()
            if coordinator?.parent.isFocused == true { coordinator?.synchronizeFocus() }
        }
        textView.onMoveSuggestionSelection = { [weak coordinator = context.coordinator] direction in
            coordinator?.parent.moveSuggestionSelection(direction) ?? false
        }
        textView.onApplySelectedSuggestion = { [weak coordinator = context.coordinator] in
            coordinator?.parent.applySelectedSuggestion() ?? false
        }
        textView.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.submit()
        }
        textView.onPasteAttachment = { [weak coordinator = context.coordinator] in
            coordinator?.parent.pasteAttachment() ?? false
        }
        textView.onOpenReference = { [weak coordinator = context.coordinator] in coordinator?.parent.openReference?($0) }
        textView.onImportReferences = { [weak coordinator = context.coordinator] in coordinator?.parent.registerReferences($0) }

        configure(scrollView: scrollView, textView: textView, style: nativeStyle)
        textView.setStyledText(text, style: nativeStyle, references: references)
        textView.setSelectedRange(
            textView.displayRange(for: ChatComposerNativeSelection.nativeRange(from: selection, in: text)
                ?? NSRange(location: (text as NSString).length, length: 0)
            )
        )
        context.coordinator.updateHeight()
        return scrollView
    }

    static func makeTextView() -> ComposerNSTextView {
        // NSTextView(frame:textContainer:) does not create a TextKit stack when
        // passed nil. Build the stack explicitly so keyboard input has storage
        // and layout objects to update.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        return ComposerNSTextView(frame: .zero, textContainer: textContainer)
    }

    func updateNSView(_ scrollView: ComposerNSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        coordinator.isApplyingUpdate = true
        defer { coordinator.isApplyingUpdate = false }

        let style = nativeStyle
        configure(scrollView: scrollView, textView: textView, style: style)

        let canReplaceText = !textView.hasMarkedText() || text.isEmpty
        if canReplaceText {
            let presentation = ComposerReferencePresentation.attributed(text, references: references, style: style)
            let didReplaceText = textView.rawText != text || textView.string != presentation.string
                || textView.referenceMetadata != references || !textView.matchesStyle(style)
            if didReplaceText {
                textView.setStyledText(text, style: style, references: references, presentation: presentation)
            } else {
                textView.applyStyle(style)
            }

            let rawSelection = ChatComposerNativeSelection.nativeRange(
                from: selection,
                in: text
            ) ?? (didReplaceText
                ? NSRange(location: (text as NSString).length, length: 0)
                : textView.rawSelectedRange)
            let targetSelection = textView.displayRange(for: rawSelection)
            if textView.selectedRange() != targetSelection {
                textView.setSelectedRange(targetSelection)
            }
        }

        coordinator.synchronizeFocus()
        coordinator.updateHeight()
    }

    static func dismantleNSView(
        _ scrollView: ComposerNSScrollView,
        coordinator: Coordinator
    ) {
        coordinator.textView?.delegate = nil
        coordinator.textView?.onLayout = nil
        coordinator.textView?.onFocusChanged = nil
        coordinator.textView?.onMoveSuggestionSelection = nil
        coordinator.textView?.onApplySelectedSuggestion = nil
        coordinator.textView?.onSubmit = nil
        coordinator.textView?.onPasteAttachment = nil
        coordinator.textView?.onOpenReference = nil
        coordinator.textView?.onImportReferences = nil
        scrollView.onLayout = nil
    }

    private var nativeStyle: AppKitComposerTextStyle {
        AppKitComposerTextStyle(
            font: .systemFont(ofSize: fontSize),
            primaryColor: NSColor(primaryColor),
            placeholderColor: NSColor(placeholderColor),
            commandColor: NSColor(commandColor),
            mentionColor: NSColor(mentionColor),
            tagColor: NSColor(tagColor),
            codeBackgroundColor: NSColor(codeBackgroundColor)
        )
    }

    private func configure(
        scrollView: ComposerNSScrollView,
        textView: ComposerNSTextView,
        style: AppKitComposerTextStyle
    ) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = textContainerInset
        textView.textContainer?.lineFragmentPadding = lineFragmentPadding
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = placeholder
        textView.placeholderLabel.textColor = style.placeholderColor
        textView.placeholderLabel.font = style.font
        textView.insertionPointColor = .white
        textView.setAccessibilityLabel(placeholder)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppKitChatComposerTextEditor
        weak var scrollView: ComposerNSScrollView?
        weak var textView: ComposerNSTextView?
        var isApplyingUpdate = false
        private var pendingHeight: CGFloat?
        private var isHeightUpdateScheduled = false
        private var isUpdatingLayout = false

        init(parent: AppKitChatComposerTextEditor) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let storage = textView.textStorage, charIndex >= 0, charIndex < storage.length,
                  let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? ComposerReferenceAttachment else { return false }
            parent.openReference?(attachment.reference)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? ComposerNSTextView else { return }

            if !textView.hasMarkedText() {
                textView.applyStyle(parent.nativeStyle, force: true)
            }
            let updatedText = textView.rawText
            let updatedRange = textView.rawSelectedRange
            parent.registerReferences(textView.inlineReferences)
            parent.cursorOffsetChanged(
                ChatComposerNativeSelection.characterOffset(
                    forUTF16Location: updatedRange.location,
                    in: updatedText
                )
            )
            parent.text = updatedText
            parent.selection = ChatComposerNativeSelection.textSelection(
                from: updatedRange,
                in: updatedText
            )
            updateHeight()
            if !textView.hasMarkedText() { parent.onCommittedText?(updatedText) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? ComposerNSTextView else { return }
            let updatedText = textView.rawText
            let updatedRange = textView.rawSelectedRange
            parent.selection = ChatComposerNativeSelection.textSelection(
                from: updatedRange,
                in: updatedText
            )
            parent.cursorOffsetChanged(
                ChatComposerNativeSelection.characterOffset(
                    forUTF16Location: updatedRange.location,
                    in: updatedText
                )
            )
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func synchronizeFocus() {
            guard let textView else { return }
            if parent.isFocused, textView.window?.firstResponder !== textView {
                if textView.window?.makeFirstResponder(textView) != true {
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self, let textView, self.parent.isFocused else { return }
                        textView.window?.makeFirstResponder(textView)
                    }
                }
            } else if !parent.isFocused, textView.window?.firstResponder === textView {
                textView.window?.makeFirstResponder(nil)
            }
        }

        func updateHeight() {
            guard !isUpdatingLayout,
                  let scrollView,
                  let textView else { return }
            let contentWidth = scrollView.contentSize.width
            guard contentWidth > 0 else { return }

            isUpdatingLayout = true
            defer { isUpdatingLayout = false }

            if abs(textView.frame.width - contentWidth) > 0.5 {
                textView.setFrameSize(NSSize(width: contentWidth, height: textView.frame.height))
            }
            if let textContainer = textView.textContainer,
               let layoutManager = textView.layoutManager {
                layoutManager.ensureLayout(for: textContainer)
                let usedHeight = layoutManager.usedRect(for: textContainer).height
                let style = parent.nativeStyle
                let lineHeight = layoutManager.defaultLineHeight(for: style.font)
                let verticalInsets = textView.textContainerInset.height * 2
                let minimumHeight = ceil(lineHeight + verticalInsets)
                let fittingHeight = max(minimumHeight, ceil(usedHeight + verticalInsets))
                let maximumHeight = ceil(
                    lineHeight * CGFloat(parent.maximumVisibleLines) + verticalInsets
                )
                let clampedHeight = min(fittingHeight, maximumHeight)
                let shouldScroll = fittingHeight > maximumHeight + 0.5
                if scrollView.hasVerticalScroller != shouldScroll {
                    scrollView.hasVerticalScroller = shouldScroll
                }
                let documentHeight = max(fittingHeight, scrollView.contentSize.height)
                if abs(textView.frame.height - documentHeight) > 0.5 {
                    textView.setFrameSize(NSSize(width: contentWidth, height: documentHeight))
                }
                scheduleHeightUpdate(clampedHeight)
            }
        }

        private func scheduleHeightUpdate(_ height: CGFloat) {
            pendingHeight = height
            guard !isHeightUpdateScheduled else { return }
            isHeightUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHeightUpdateScheduled = false
                guard let height = self.pendingHeight else { return }
                self.pendingHeight = nil
                if abs(self.parent.measuredHeight - height) > 0.5 {
                    self.parent.measuredHeight = height
                }
            }
        }
    }
}

struct AppKitComposerTextStyle: Equatable {
    let font: NSFont
    let primaryColor: NSColor
    let placeholderColor: NSColor
    let commandColor: NSColor
    let mentionColor: NSColor
    let tagColor: NSColor
    let codeBackgroundColor: NSColor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.font.isEqual(rhs.font)
            && lhs.primaryColor.isEqual(rhs.primaryColor)
            && lhs.placeholderColor.isEqual(rhs.placeholderColor)
            && lhs.commandColor.isEqual(rhs.commandColor)
            && lhs.mentionColor.isEqual(rhs.mentionColor)
            && lhs.tagColor.isEqual(rhs.tagColor)
            && lhs.codeBackgroundColor.isEqual(rhs.codeBackgroundColor)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: primaryColor,
        ]
    }
}

@MainActor
final class ComposerNSScrollView: NSScrollView {
    var onLayout: (@MainActor () -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

@MainActor
final class ComposerNSTextView: NSTextView {
    static func pasteboardContainsAttachment(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            return true
        }
        return ChatComposerPasteboard.containsAttachmentType(
            pasteboard.types?.map(\.rawValue) ?? []
        )
    }

    static func shouldEnableAttachmentPaste(
        action: Selector?,
        pasteboard: NSPasteboard
    ) -> Bool {
        action == #selector(paste(_:)) && pasteboardContainsAttachment(pasteboard)
    }

    let placeholderLabel = ComposerPlaceholderLabel(labelWithString: "")
    var placeholder: String? {
        didSet {
            placeholderLabel.stringValue = placeholder ?? ""
            updatePlaceholderVisibility()
        }
    }
    var onFocusChanged: (@MainActor (Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChanged?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChanged?(false) }
        return accepted
    }
    var onLayout: (@MainActor () -> Void)?
    var onMoveSuggestionSelection: (@MainActor (ChatComposerSuggestionSelectionDirection) -> Bool)?
    var onApplySelectedSuggestion: (@MainActor () -> Bool)?
    var onSubmit: (@MainActor () -> Void)?
    var onPasteAttachment: (@MainActor () -> Bool)?
    var onOpenReference: (@MainActor (ChatComposerReference) -> Void)?
    var onImportReferences: (@MainActor ([ChatComposerReference]) -> Void)?
    private(set) var referenceMetadata: [ChatComposerReference] = []

    var rawText: String { ComposerReferenceProjection(attributedString()).rawText }
    var rawSelectedRange: NSRange { ComposerReferenceProjection(attributedString()).rawRange(selectedRange()) }
    func displayRange(for rawRange: NSRange) -> NSRange {
        ComposerReferenceProjection(attributedString()).displayRange(rawRange)
    }
    var inlineReferences: [ChatComposerReference] {
        Self.references(in: attributedString())
    }
    private static func references(in text: NSAttributedString) -> [ChatComposerReference] {
        var values: [ChatComposerReference] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let attachment = value as? ComposerReferenceAttachment { values.append(attachment.reference) }
        }
        return values
    }

    private var appliedStyle: AppKitComposerTextStyle?
    func matchesStyle(_ style: AppKitComposerTextStyle) -> Bool { appliedStyle == style }
    private var codeBlockRanges: [NSRange] = []

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override func layout() {
        super.layout()
        layoutPlaceholder()
        onLayout?()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let appliedStyle, let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin

        for range in codeBlockRanges {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { continue }

            var glyphIndex = glyphRange.location
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            while glyphIndex < NSMaxRange(glyphRange) {
                var lineRange = NSRange(location: 0, length: 0)
                let fragment = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &lineRange
                )
                minY = min(minY, fragment.minY)
                maxY = max(maxY, fragment.maxY)
                let nextIndex = NSMaxRange(lineRange)
                guard nextIndex > glyphIndex else { break }
                glyphIndex = nextIndex
            }

            let x = max(2, origin.x - 4)
            let background = NSRect(
                x: x,
                y: origin.y + minY - 2,
                width: max(0, bounds.width - 2 * x),
                height: max(0, maxY - minY + 4)
            )
            guard background.intersects(rect) else { continue }
            appliedStyle.codeBackgroundColor.setFill()
            NSBezierPath(roundedRect: background, xRadius: 7, yRadius: 7).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, !event.modifierFlags.contains(.shift), let onOpenReference,
           let reference = reference(at: convert(event.locationInWindow, from: nil)) {
            onOpenReference(reference)
            return
        }
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            if onMoveSuggestionSelection?(.previous) == true { return }
        case 125:
            if onMoveSuggestionSelection?(.next) == true { return }
        case 36, 76:
            if event.modifierFlags.contains(.shift) {
                insertText("\n", replacementRange: selectedRange())
            } else if onApplySelectedSuggestion?() != true {
                onSubmit?()
            }
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: Self.referencePasteboardType),
           let references = try? JSONDecoder().decode([ChatComposerReference].self, from: data),
           let text = pasteboard.string(forType: .string) {
            onImportReferences?(references)
            insertText(text, replacementRange: selectedRange())
            return
        }
        if Self.pasteboardContainsAttachment(.general),
           onPasteAttachment?() == true {
            return
        }
        super.paste(sender)
    }

    static let referencePasteboardType = NSPasteboard.PasteboardType("team.sloppy.composer-references")
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string, Self.referencePasteboardType] }

    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let selected = attributedString().attributedSubstring(from: selectedRange())
        if type == .string { return pasteboard.setString(ComposerReferenceProjection(selected).rawText, forType: .string) }
        if type == Self.referencePasteboardType, let data = try? JSONEncoder().encode(Self.references(in: selected)) {
            return pasteboard.setData(data, forType: type)
        }
        return super.writeSelection(to: pasteboard, type: type)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager, let textContainer else { return }
        let value = attributedString()
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attachment, range, _ in
            guard attachment is ComposerReferenceAttachment else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    private func reference(at point: NSPoint) -> ChatComposerReference? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < textStorage.length,
              let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? ComposerReferenceAttachment else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        guard layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(location) else { return nil }
        return attachment.reference
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if Self.shouldEnableAttachmentPaste(action: item.action, pasteboard: .general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if Self.shouldEnableAttachmentPaste(action: menuItem.action, pasteboard: .general) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    func setStyledText(_ text: String, style: AppKitComposerTextStyle, references: [ChatComposerReference] = [], presentation: NSAttributedString? = nil) {
        let selectedRange = rawSelectedRange
        let value = presentation ?? ComposerReferencePresentation.attributed(text, references: references, style: style)
        textStorage?.setAttributedString(value)
        referenceMetadata = references
        appliedStyle = style
        typingAttributes = style.baseAttributes
        setSelectedRange(displayRange(for: clamped(selectedRange, for: text)))
        applyStyle(style, force: true)
        updatePlaceholderVisibility()
        needsDisplay = true
    }

    func applyStyle(_ style: AppKitComposerTextStyle, force: Bool = false) {
        guard force || appliedStyle != style,
              let textStorage else { return }
        let selectedRange = selectedRange()
        let text = string
        codeBlockRanges = ChatComposerCodeFence.ranges(in: text)
        textStorage.beginEditing()
        let snapshot = NSAttributedString(attributedString: textStorage)
        snapshot.enumerateAttribute(.attachment, in: NSRange(location: 0, length: snapshot.length)) { value, range, _ in
            if let attachment = value as? ComposerReferenceAttachment {
                textStorage.setAttributes([.attachment: attachment, .font: style.font, .toolTip: attachment.reference.rawText,
                                           .link: ComposerReferencePresentation.link(for: attachment.reference)], range: range)
            } else {
                textStorage.setAttributes(style.baseAttributes, range: range)
            }
        }
        applyTokenColors(to: textStorage, text: text, style: style)
        textStorage.endEditing()
        appliedStyle = style
        typingAttributes = style.baseAttributes
        setSelectedRange(clamped(selectedRange, for: text))
        updatePlaceholderVisibility()
        needsDisplay = true
    }

    private func setUp() {
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isBordered = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        addSubview(placeholderLabel)
    }

    private func layoutPlaceholder() {
        placeholderLabel.sizeToFit()
        let linePadding = textContainer?.lineFragmentPadding ?? 0
        placeholderLabel.frame.origin = CGPoint(
            x: textContainerInset.width + linePadding,
            y: textContainerInset.height
        )
        placeholderLabel.frame.size.width = max(
            0,
            bounds.width - placeholderLabel.frame.minX - textContainerInset.width
        )
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !string.isEmpty
    }

    private func applyTokenColors(
        to result: NSMutableAttributedString,
        text: String,
        style: AppKitComposerTextStyle
    ) {
        for token in ChatComposerToken.parseAll(in: text) {
            let color: NSColor = switch token.kind {
            case .command: style.commandColor
            case .mention: style.mentionColor
            case .tag: style.tagColor
            }
            result.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(token.range, in: text)
            )
        }
        for range in codeBlockRanges {
            result.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: style.font.pointSize, weight: .regular),
                .foregroundColor: style.primaryColor,
                .backgroundColor: style.codeBackgroundColor,
            ], range: range)
        }
    }

    private func clamped(_ range: NSRange, for text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        return NSRange(
            location: location,
            length: min(max(range.length, 0), length - location)
        )
    }
}

@MainActor
final class ComposerPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif
