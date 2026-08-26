import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum ChatComposerNativeSelection {
    static func nativeRange(
        from selection: TextSelection?,
        in text: String
    ) -> NSRange? {
        guard let selection else { return nil }

        let range: Range<String.Index>?
        switch selection.indices {
        case .selection(let selectedRange):
            range = selectedRange
        case .multiSelection(let selectedRanges):
            range = selectedRanges.ranges.first
        @unknown default:
            range = nil
        }

        guard let range else { return nil }
        return NSRange(range, in: text)
    }

    static func textSelection(
        from range: NSRange,
        in text: String
    ) -> TextSelection? {
        guard let stringRange = Range(range, in: text) else { return nil }
        if range.length == 0 {
            return TextSelection(insertionPoint: stringRange.lowerBound)
        }
        return TextSelection(range: stringRange)
    }

    static func characterOffset(
        forUTF16Location location: Int,
        in text: String
    ) -> Int? {
        guard location >= 0,
              location <= text.utf16.count,
              let range = Range(NSRange(location: location, length: 0), in: text) else {
            return nil
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}

#if canImport(UIKit) && !os(macOS)
struct UIKitChatComposerTextEditor: UIViewRepresentable {
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
    let maximumVisibleLines: Int
    let textContainerInset: EdgeInsets
    let lineFragmentPadding: CGFloat
    let cursorOffsetChanged: @MainActor (Int?) -> Void
    let moveSuggestionSelection: @MainActor (ChatComposerSuggestionSelectionDirection) -> Bool
    let applySelectedSuggestion: @MainActor () -> Bool
    let submit: @MainActor () -> Void
    let pasteItemProviders: @MainActor ([NSItemProvider]) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerUITextView {
        let textView = ComposerUITextView(frame: .zero, textContainer: nil)
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.onLayout = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.updateHeight(textView)
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
        textView.onPasteItemProviders = { [weak coordinator = context.coordinator] providers in
            coordinator?.parent.pasteItemProviders(providers) ?? false
        }

        configure(textView, style: nativeStyle)
        textView.setStyledText(text, style: nativeStyle)
        textView.selectedRange = ChatComposerNativeSelection.nativeRange(
            from: selection,
            in: text
        ) ?? NSRange(location: (text as NSString).length, length: 0)
        context.coordinator.updateHeight(textView)
        return textView
    }

    func updateUIView(_ textView: ComposerUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isApplyingUpdate = true
        defer { coordinator.isApplyingUpdate = false }

        let style = nativeStyle
        configure(textView, style: style)

        let canReplaceText = textView.markedTextRange == nil || text.isEmpty
        if canReplaceText {
            let didReplaceText = textView.text != text
            if didReplaceText {
                textView.setStyledText(text, style: style)
            } else {
                textView.applyStyle(style)
            }

            let targetSelection = ChatComposerNativeSelection.nativeRange(
                from: selection,
                in: text
            ) ?? (didReplaceText
                ? NSRange(location: (text as NSString).length, length: 0)
                : textView.selectedRange)
            if textView.selectedRange != targetSelection {
                textView.selectedRange = targetSelection
            }
        }

        coordinator.synchronizeFocus(textView)
        coordinator.updateHeight(textView)
    }

    static func dismantleUIView(
        _ textView: ComposerUITextView,
        coordinator: Coordinator
    ) {
        textView.delegate = nil
        textView.onLayout = nil
        textView.onMoveSuggestionSelection = nil
        textView.onApplySelectedSuggestion = nil
        textView.onSubmit = nil
        textView.onPasteItemProviders = nil
    }

    private var nativeStyle: UIKitComposerTextStyle {
        UIKitComposerTextStyle(
            font: .systemFont(ofSize: fontSize),
            primaryColor: UIColor(primaryColor),
            placeholderColor: UIColor(placeholderColor),
            commandColor: UIColor(commandColor),
            mentionColor: UIColor(mentionColor),
            tagColor: UIColor(tagColor)
        )
    }

    private func configure(
        _ textView: ComposerUITextView,
        style: UIKitComposerTextStyle
    ) {
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: textContainerInset.top,
            left: textContainerInset.leading,
            bottom: textContainerInset.bottom,
            right: textContainerInset.trailing
        )
        textView.textContainer.lineFragmentPadding = lineFragmentPadding
        textView.placeholder = placeholder
        textView.placeholderLabel.textColor = style.placeholderColor
        textView.placeholderLabel.font = style.font
        textView.tintColor = .white
        textView.returnKeyType = .send
        #if !os(visionOS)
        textView.keyboardDismissMode = .interactive
        #endif
        textView.adjustsFontForContentSizeCategory = false
        textView.accessibilityLabel = placeholder
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: UIKitChatComposerTextEditor
        weak var textView: ComposerUITextView?
        var isApplyingUpdate = false
        private var pendingHeight: CGFloat?
        private var isHeightUpdateScheduled = false

        init(parent: UIKitChatComposerTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingUpdate,
                  let textView = textView as? ComposerUITextView else { return }

            if textView.markedTextRange == nil {
                textView.applyStyle(parent.nativeStyle, force: true)
            }
            let updatedText = textView.text ?? ""
            let updatedRange = textView.selectedRange
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
            updateHeight(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingUpdate else { return }
            let updatedText = textView.text ?? ""
            parent.selection = ChatComposerNativeSelection.textSelection(
                from: textView.selectedRange,
                in: updatedText
            )
            parent.cursorOffsetChanged(
                ChatComposerNativeSelection.characterOffset(
                    forUTF16Location: textView.selectedRange.location,
                    in: updatedText
                )
            )
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n",
                  textView.markedTextRange == nil,
                  let textView = textView as? ComposerUITextView,
                  !textView.isInsertingModifiedNewline else {
                return true
            }

            if parent.applySelectedSuggestion() {
                return false
            }
            parent.submit()
            return false
        }

        func synchronizeFocus(_ textView: ComposerUITextView) {
            if parent.isFocused, !textView.isFirstResponder {
                if !textView.becomeFirstResponder() {
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self, let textView, self.parent.isFocused else { return }
                        textView.becomeFirstResponder()
                    }
                }
            } else if !parent.isFocused, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        func updateHeight(_ textView: ComposerUITextView) {
            let width = textView.bounds.width
            guard width > 0 else { return }

            let style = parent.nativeStyle
            let fittingHeight = textView.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
            let verticalInsets = textView.textContainerInset.top
                + textView.textContainerInset.bottom
            let minimumHeight = ceil(style.font.lineHeight + verticalInsets)
            let maximumHeight = ceil(
                style.font.lineHeight * CGFloat(parent.maximumVisibleLines)
                    + verticalInsets
            )
            let clampedHeight = min(max(fittingHeight, minimumHeight), maximumHeight)
            let shouldScroll = fittingHeight > maximumHeight + 0.5
            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
                textView.showsVerticalScrollIndicator = shouldScroll
            }
            scheduleHeightUpdate(clampedHeight)
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

struct UIKitComposerTextStyle: Equatable {
    let font: UIFont
    let primaryColor: UIColor
    let placeholderColor: UIColor
    let commandColor: UIColor
    let mentionColor: UIColor
    let tagColor: UIColor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.font.isEqual(rhs.font)
            && lhs.primaryColor.isEqual(rhs.primaryColor)
            && lhs.placeholderColor.isEqual(rhs.placeholderColor)
            && lhs.commandColor.isEqual(rhs.commandColor)
            && lhs.mentionColor.isEqual(rhs.mentionColor)
            && lhs.tagColor.isEqual(rhs.tagColor)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: primaryColor,
        ]
    }
}

@MainActor
final class ComposerUITextView: UITextView {
    let placeholderLabel = UILabel()
    var placeholder: String? {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholderVisibility()
        }
    }
    var onLayout: (@MainActor () -> Void)?
    var onMoveSuggestionSelection: (@MainActor (ChatComposerSuggestionSelectionDirection) -> Bool)?
    var onApplySelectedSuggestion: (@MainActor () -> Bool)?
    var onSubmit: (@MainActor () -> Void)?
    var onPasteItemProviders: (@MainActor ([NSItemProvider]) -> Bool)?
    var isInsertingModifiedNewline = false

    private var appliedStyle: UIKitComposerTextStyle?
    private var placeholderTopConstraint: NSLayoutConstraint?
    private var placeholderLeadingConstraint: NSLayoutConstraint?
    private var placeholderTrailingConstraint: NSLayoutConstraint?
    private var previousLayoutWidth: CGFloat = 0
    private var previousContentSize: CGSize = .zero

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var textContainerInset: UIEdgeInsets {
        didSet {
            updatePlaceholderConstraints()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(previousLayoutWidth - bounds.width) > 0.5
            || previousContentSize != contentSize {
            previousLayoutWidth = bounds.width
            previousContentSize = contentSize
            onLayout?()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.count == 1,
              let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }

        switch key.charactersIgnoringModifiers {
        case UIKeyCommand.inputUpArrow:
            if onMoveSuggestionSelection?(.previous) == true { return }
        case UIKeyCommand.inputDownArrow:
            if onMoveSuggestionSelection?(.next) == true { return }
        case "\r", "\n":
            if key.modifierFlags.contains(.shift) {
                isInsertingModifiedNewline = true
                insertText("\n")
                isInsertingModifiedNewline = false
            } else if onApplySelectedSuggestion?() != true {
                onSubmit?()
            }
            return
        default:
            break
        }

        super.pressesBegan(presses, with: event)
    }

    override func paste(_ sender: Any?) {
        let providers = UIPasteboard.general.itemProviders
        if !providers.isEmpty, onPasteItemProviders?(providers) == true {
            return
        }
        super.paste(sender)
    }

    func setStyledText(_ text: String, style: UIKitComposerTextStyle) {
        let selectedRange = selectedRange
        attributedText = styledText(text, style: style)
        appliedStyle = style
        typingAttributes = style.baseAttributes
        self.selectedRange = clamped(selectedRange, for: text)
        updatePlaceholderVisibility()
    }

    func applyStyle(_ style: UIKitComposerTextStyle, force: Bool = false) {
        guard force || appliedStyle != style else { return }
        let selectedRange = selectedRange
        let text = self.text ?? ""
        textStorage.beginEditing()
        textStorage.setAttributes(
            style.baseAttributes,
            range: NSRange(location: 0, length: textStorage.length)
        )
        applyTokenColors(to: textStorage, text: text, style: style)
        textStorage.endEditing()
        appliedStyle = style
        typingAttributes = style.baseAttributes
        self.selectedRange = clamped(selectedRange, for: text)
        updatePlaceholderVisibility()
    }

    private func setUp() {
        backgroundColor = .clear
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        textAlignment = .natural

        placeholderLabel.numberOfLines = 1
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        placeholderTopConstraint = placeholderLabel.topAnchor.constraint(
            equalTo: topAnchor,
            constant: textContainerInset.top
        )
        placeholderLeadingConstraint = placeholderLabel.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: textContainerInset.left + textContainer.lineFragmentPadding
        )
        placeholderTrailingConstraint = placeholderLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -(textContainerInset.right + textContainer.lineFragmentPadding)
        )
        NSLayoutConstraint.activate([
            placeholderTopConstraint,
            placeholderLeadingConstraint,
            placeholderTrailingConstraint,
        ].compactMap { $0 })
    }

    private func updatePlaceholderConstraints() {
        placeholderTopConstraint?.constant = textContainerInset.top
        placeholderLeadingConstraint?.constant = textContainerInset.left
            + textContainer.lineFragmentPadding
        placeholderTrailingConstraint?.constant = -(
            textContainerInset.right + textContainer.lineFragmentPadding
        )
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
    }

    private func styledText(
        _ text: String,
        style: UIKitComposerTextStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: style.baseAttributes)
        applyTokenColors(to: result, text: text, style: style)
        return result
    }

    private func applyTokenColors(
        to result: NSMutableAttributedString,
        text: String,
        style: UIKitComposerTextStyle
    ) {
        for token in ChatComposerToken.parseAll(in: text) {
            let color: UIColor = switch token.kind {
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
    let maximumVisibleLines: Int
    let textContainerInset: CGSize
    let lineFragmentPadding: CGFloat
    let cursorOffsetChanged: @MainActor (Int?) -> Void
    let moveSuggestionSelection: @MainActor (ChatComposerSuggestionSelectionDirection) -> Bool
    let applySelectedSuggestion: @MainActor () -> Bool
    let submit: @MainActor () -> Void
    let pasteAttachment: @MainActor () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ComposerNSScrollView {
        let scrollView = ComposerNSScrollView()
        let textView = Self.makeTextView()
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateHeight()
        }
        textView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateHeight()
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

        configure(scrollView: scrollView, textView: textView, style: nativeStyle)
        textView.setStyledText(text, style: nativeStyle)
        textView.setSelectedRange(
            ChatComposerNativeSelection.nativeRange(from: selection, in: text)
                ?? NSRange(location: (text as NSString).length, length: 0)
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
            let didReplaceText = textView.string != text
            if didReplaceText {
                textView.setStyledText(text, style: style)
            } else {
                textView.applyStyle(style)
            }

            let targetSelection = ChatComposerNativeSelection.nativeRange(
                from: selection,
                in: text
            ) ?? (didReplaceText
                ? NSRange(location: (text as NSString).length, length: 0)
                : textView.selectedRange())
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
        coordinator.textView?.onMoveSuggestionSelection = nil
        coordinator.textView?.onApplySelectedSuggestion = nil
        coordinator.textView?.onSubmit = nil
        coordinator.textView?.onPasteAttachment = nil
        scrollView.onLayout = nil
    }

    private var nativeStyle: AppKitComposerTextStyle {
        AppKitComposerTextStyle(
            font: .systemFont(ofSize: fontSize),
            primaryColor: NSColor(primaryColor),
            placeholderColor: NSColor(placeholderColor),
            commandColor: NSColor(commandColor),
            mentionColor: NSColor(mentionColor),
            tagColor: NSColor(tagColor)
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

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? ComposerNSTextView else { return }

            if !textView.hasMarkedText() {
                textView.applyStyle(parent.nativeStyle, force: true)
            }
            let updatedText = textView.string
            let updatedRange = textView.selectedRange()
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? NSTextView else { return }
            let updatedText = textView.string
            let updatedRange = textView.selectedRange()
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.font.isEqual(rhs.font)
            && lhs.primaryColor.isEqual(rhs.primaryColor)
            && lhs.placeholderColor.isEqual(rhs.placeholderColor)
            && lhs.commandColor.isEqual(rhs.commandColor)
            && lhs.mentionColor.isEqual(rhs.mentionColor)
            && lhs.tagColor.isEqual(rhs.tagColor)
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
    let placeholderLabel = ComposerPlaceholderLabel(labelWithString: "")
    var placeholder: String? {
        didSet {
            placeholderLabel.stringValue = placeholder ?? ""
            updatePlaceholderVisibility()
        }
    }
    var onLayout: (@MainActor () -> Void)?
    var onMoveSuggestionSelection: (@MainActor (ChatComposerSuggestionSelectionDirection) -> Bool)?
    var onApplySelectedSuggestion: (@MainActor () -> Bool)?
    var onSubmit: (@MainActor () -> Void)?
    var onPasteAttachment: (@MainActor () -> Bool)?

    private var appliedStyle: AppKitComposerTextStyle?

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

    override func mouseDown(with event: NSEvent) {
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
        if onPasteAttachment?() == true { return }
        super.paste(sender)
    }

    func setStyledText(_ text: String, style: AppKitComposerTextStyle) {
        let selectedRange = selectedRange()
        textStorage?.setAttributedString(styledText(text, style: style))
        appliedStyle = style
        typingAttributes = style.baseAttributes
        setSelectedRange(clamped(selectedRange, for: text))
        updatePlaceholderVisibility()
    }

    func applyStyle(_ style: AppKitComposerTextStyle, force: Bool = false) {
        guard force || appliedStyle != style,
              let textStorage else { return }
        let selectedRange = selectedRange()
        let text = string
        textStorage.beginEditing()
        textStorage.setAttributes(
            style.baseAttributes,
            range: NSRange(location: 0, length: textStorage.length)
        )
        applyTokenColors(to: textStorage, text: text, style: style)
        textStorage.endEditing()
        appliedStyle = style
        typingAttributes = style.baseAttributes
        setSelectedRange(clamped(selectedRange, for: text))
        updatePlaceholderVisibility()
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

    private func styledText(
        _ text: String,
        style: AppKitComposerTextStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: style.baseAttributes)
        applyTokenColors(to: result, text: text, style: style)
        return result
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
