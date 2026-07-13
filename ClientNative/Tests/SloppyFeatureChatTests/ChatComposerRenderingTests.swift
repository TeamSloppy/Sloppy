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
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/Views/ChatComposerView.swift")
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
        #expect(source.contains(".frame("))
        #expect(source.contains("width: ChatComposerView.phoneCircleSize"))
        #expect(source.contains("height: ChatComposerView.phoneCircleSize"))
        #expect(source.contains(".buttonBorderShape(.circle)"))
        #expect(source.contains(".buttonStyle(.glass)"))
    }

    @Test("composer add button exposes platform-specific picker menus")
    func composerAddButtonExposesPlatformSpecificPickerMenus() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct ComposerAddMenu"))
        #expect(source.contains("Label(\"Files and Attach\""))
        #expect(source.contains("Label(\"Model\""))
        #expect(source.contains("Label(\"Camera\""))
        #expect(source.contains("Label(\"Photos\""))
        #expect(source.contains("Label(\"Files\""))
        #expect(source.contains("Label(\"Agent\""))
        #expect(source.contains("Label(\"Effort\""))
        #expect(source.contains(".menuIndicator(.hidden)"))
        #expect(source.contains(".menuStyle(.button)"))
    }

    @Test("chat composer phone layout exposes tab action hooks")
    func chatComposerPhoneLayoutExposesTabActionHooks() throws {
        let source = try chatComposerSource

        #expect(source.contains("public struct ChatComposerTabActions"))
        #expect(source.contains("public let tabActions: ChatComposerTabActions?"))
        #expect(source.contains("tabActions?.tabProgress(newValue)"))
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
        #expect(source.contains(".onSubmit {"))
    }

    @Test("composer draft is observable so trailing action reacts while typing")
    func composerDraftIsObservable() throws {
        let source = try chatComposerSource

        #expect(source.contains("@Observable"))
        #expect(source.contains("@Bindable public var draft: ChatComposerDraft"))
        #expect(source.contains("@Bindable var draft: ChatComposerDraft"))
        #expect(source.contains("ChatTextField("))
        #expect(source.contains("draft: draft,"))
        #expect(source.contains("text: $draft.text"))
    }

    @Test("composer command suggestions use a full-size panel")
    func composerSuggestionsUseFullSizePanel() throws {
        let source = try chatComposerSource

        #expect(source.contains("private static let panelHeight: CGFloat = 320"))
        #expect(source.contains("minHeight: Self.panelHeight"))
        #expect(source.contains("maxHeight: Self.panelHeight"))
        #expect(source.contains(".overlay(alignment: .bottom)"))
    }

    @Test("composer trailing action swaps between dictation send and stop")
    func composerTrailingActionSupportsDictationSendingAndStoppingRuns() throws {
        let source = try chatComposerSource

        #expect(source.contains("DictationComposerBar("))
        #expect(source.contains("if viewModel.isShowingDictationComposer"))
        #expect(source.contains("return .arrowUpward"))
        #expect(source.contains("viewModel.startDictation()"))
        #expect(source.contains("stop: viewModel.stopDictation"))
        #expect(source.contains("viewModel.stopActiveRun()"))
        #expect(source.contains("guard !trimmed.isEmpty, viewModel.canSubmitMessage else { return }"))
    }

    @Test("composer dictation bar replaces controls with waveform timer and stop button")
    func composerDictationBarReplacesControls() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct DictationComposerBar"))
        #expect(source.contains("ForEach(levels.indices, id: \\.self)"))
        #expect(source.contains("Text(elapsedText)"))
        #expect(source.contains("Icons.symbol(.stop"))
        #expect(!source.contains("draft.requestDictation()"))
    }

    @Test("dictation bar keeps trailing controls fixed while waveform can overflow left")
    func dictationBarKeepsTrailingControlsFixed() throws {
        let source = try chatComposerSource

        #expect(source.contains("private let elapsedTextWidth: CGFloat = 64"))
        #expect(source.contains("private let stopButtonSize: CGFloat = 32"))
        #expect(source.contains("private var trailingControlsWidth: CGFloat {"))
        #expect(source.contains("elapsedTextWidth + theme.spacing.s + stopButtonSize"))
        #expect(source.contains("waveformViewport"))
        #expect(source.contains("waveformView"))
        #expect(source.contains("trailingControls"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
        #expect(source.contains(".overlay(alignment: .trailing)"))
        #expect(source.contains("Color.clear"))
        #expect(source.contains(".allowsHitTesting(false)"))
    }

    @Test("desktop composer exposes one combined model effort and agent menu")
    func desktopComposerExposesOneCombinedModelEffortAndAgentMenu() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct ComposerOptionsMenuView"))
        #expect(source.contains("Section(\"Model\")"))
        #expect(source.contains("Section(\"Reasoning\")"))
        #expect(source.contains("Section(\"Agent\")"))
        #expect(source.contains("private struct ComposerMenuItem"))
        #expect(source.contains("private var selectedModelTitle: String"))
        #expect(!source.contains("ModelPickerView("))
        #expect(!source.contains("ReasoningEffortPickerView("))
        #expect(!source.contains("AgentPickerView("))
    }
}
