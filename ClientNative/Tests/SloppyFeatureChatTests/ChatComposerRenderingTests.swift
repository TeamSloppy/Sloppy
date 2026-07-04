import Foundation
import Testing

@Suite("ChatComposer rendering")
struct ChatComposerRenderingTests {
    private var chatComposerSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatComposerView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("composer text field uses white caret")
    func composerTextFieldUsesWhiteCaret() throws {
        let source = try chatComposerSource

        #expect(source.contains(".accentColor(.white)"))
    }

    @Test("mobile composer action buttons are circular")
    func mobileComposerActionButtonsAreCircular() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct MobileComposerCircleButton"))
        #expect(source.contains(".frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)"))
        #expect(source.contains("Circle()"))
        #expect(source.contains(".glassEffect(.regular, in: Circle())"))
        #expect(source.contains(".buttonStyle(DefaultButtonStyle())"))
        #expect(!source.contains(".buttonStyle(.glass)"))
    }

    @Test("chat composer phone layout exposes tab action hooks")
    func chatComposerPhoneLayoutExposesTabActionHooks() throws {
        let source = try chatComposerSource

        #expect(source.contains("public struct ChatComposerTabActions"))
        #expect(source.contains("var tabActions: ChatComposerTabActions?"))
        #expect(source.contains("tabActions?.createTab()"))
        #expect(source.contains("tabActions?.showOverview()"))
    }

    @Test("composer text fields are focusable and can be blurred externally")
    func composerTextFieldsAreFocusableAndCanBeBlurredExternally() throws {
        let source = try chatComposerSource

        #expect(source.contains("@FocusState private var isTextFieldFocused: Bool"))
        #expect(source.contains(".focused($isTextFieldFocused)"))
        #expect(source.contains(".onChange(of: viewModel.composerFocusResetToken)"))
        #expect(source.contains("isTextFieldFocused = false"))
    }

    @Test("composer submit delegates clearing to the view model send path")
    func composerSubmitDelegatesClearingToViewModelSendPath() throws {
        let source = try chatComposerSource

        #expect(source.contains("viewModel.sendMessage(content: trimmed)"))
        #expect(!source.contains("draft.text = \"\""))
    }

    @Test("composer text fields submit on enter")
    func composerTextFieldsSubmitOnEnter() throws {
        let source = try chatComposerSource

        #expect(source.contains(".submitLabel(.send)"))
        #expect(source.contains(".onSubmit(submit)"))
    }

    @Test("desktop composer exposes one combined model effort and agent menu")
    func desktopComposerExposesOneCombinedModelEffortAndAgentMenu() throws {
        let source = try chatComposerSource

        #expect(source.contains("ComposerOptionsMenuView("))
        #expect(source.contains("private struct ComposerOptionsMenuView"))
        #expect(source.contains("Section(\"Model\")"))
        #expect(source.contains("Section(\"Reasoning\")"))
        #expect(source.contains("Section(\"Agent\")"))
        #expect(source.contains("private struct ComposerMenuChip"))
        #expect(source.contains("private struct ComposerMenuItem"))
        #expect(!source.contains("ModelPickerView("))
        #expect(!source.contains("ReasoningEffortPickerView("))
        #expect(!source.contains("AgentPickerView("))
    }
}
