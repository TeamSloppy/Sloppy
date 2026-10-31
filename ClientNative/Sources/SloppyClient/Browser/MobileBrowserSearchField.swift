#if os(iOS)
import SwiftUI
import UIKit

/// One native editor keeps URL selection and IME state stable while the overlay resizes.
@MainActor
struct MobileBrowserSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var selectsAddress: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> AddressField {
        let field = AddressField()
        field.text = text
        field.attributedPlaceholder = NSAttributedString(string: "Search or enter address", attributes: [.foregroundColor: UIColor.secondaryLabel])
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.tintColor = .systemBlue
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.keyboardType = .webSearch
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityLabel = "Search or enter an address"
        field.accessibilityIdentifier = "browser-search-input"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.field = field
        field.onAttach = { [weak coordinator = context.coordinator] in coordinator?.updateFocus() }
        field.onCancel = onCancel
        return field
    }

    func updateUIView(_ field: AddressField, context: Context) {
        context.coordinator.parent = self
        if field.text != text, field.markedTextRange == nil { field.text = text }
        field.onCancel = onCancel
        context.coordinator.updateFocus()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AddressField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: max(44, uiView.font?.lineHeight ?? 44))
    }

    static func dismantleUIView(_ field: AddressField, coordinator: Coordinator) {
        field.onAttach = nil
        field.onCancel = nil
        field.delegate = nil
        field.removeTarget(coordinator, action: nil, for: .allEvents)
        field.resignFirstResponder()
    }

    final class AddressField: UITextField {
        var onAttach: (() -> Void)?
        var onCancel: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { onAttach?() } }
        override var keyCommands: [UIKeyCommand]? {
            (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelSearch))]
        }
        @objc private func cancelSearch() { onCancel?() }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MobileBrowserSearchField
        weak var field: UITextField?
        private var selectedInitialAddress = false

        init(parent: MobileBrowserSearchField) { self.parent = parent }

        func updateFocus() {
            guard let field, field.window != nil else { return }
            if parent.isFocused, !field.isFirstResponder {
                DispatchQueue.main.async { [weak self, weak field] in
                    guard self?.parent.isFocused == true, let field, field.window != nil else { return }
                    field.becomeFirstResponder()
                }
            } else if !parent.isFocused, field.isFirstResponder {
                field.resignFirstResponder()
            }
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.isFocused = true
            guard parent.selectsAddress, !selectedInitialAddress else { return }
            selectedInitialAddress = true
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder else { return }
                field.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) { parent.isFocused = false }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.text = field.text ?? ""
            parent.onSubmit()
            return false
        }
    }
}
#endif
