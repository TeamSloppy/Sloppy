#if os(macOS)
import AppKit
import SwiftUI

/// Keep one native field editor while SwiftUI updates results and selection.
@MainActor
struct BrowserSearchField: NSViewRepresentable {
    @Binding var text: String
    let selectsAddress: Bool
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onAskAgent: () -> Void
    let onClose: () -> Void


    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 23)
        field.textColor = .labelColor
        field.placeholderString = "Search or enter an address"
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.stringValue = text
        field.selectsAddress = selectsAddress
        field.setAccessibilityLabel("Search or enter an address")
        field.setAccessibilityIdentifier("browser-search-input")
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: 32)
    }

    final class Field: NSTextField {
        var selectsAddress = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                if selectsAddress { currentEditor()?.selectAll(nil) }
                else if let editor = currentEditor() as? NSTextView {
                    editor.setSelectedRange(NSRange(location: stringValue.utf16.count, length: 0))
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserSearchField
        init(_ parent: BrowserSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true { parent.onAskAgent() }
                else { parent.onSubmit() }
            case #selector(NSResponder.cancelOperation(_:)): parent.onClose()
            default: return false
            }
            return true
        }
    }
}
#endif
