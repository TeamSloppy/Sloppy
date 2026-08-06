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

    private var composerSuggestionsSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/Views/ComposerSuggestionsView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("composer text field uses white caret")
    func composerTextFieldUsesWhiteCaret() throws {
        let source = try chatComposerSource

        #expect(source.contains(".accentColor(.white)"))
        #expect(source.contains(".pointerStyle(.horizontalText)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(!source.contains(".focusable()"))
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
        #expect(source.contains("Icons.symbol(.add, size: theme.typography.heading)"))
    }

    @Test("desktop composer uses a compact single-row layout")
    func desktopComposerUsesCompactSingleRowLayout() throws {
        let source = try chatComposerSource

        #expect(source.contains("public static let panelHeight: CGFloat = Constants.fieldHeight"))
        #expect(source.contains("private static let panelRadius: CGFloat = panelHeight / 2"))
        #expect(source.contains("width: ChatComposerView.buttonSize"))
        #expect(source.contains("height: ChatComposerView.buttonSize"))
        #expect(source.contains("HStack(spacing: 0)"))
        #expect(source.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!source.contains("modelPickerBottomPadding"))
    }

    @Test("desktop add glyph is centered independently from the menu indicator")
    func desktopAddGlyphIsCenteredIndependentlyFromMenuIndicator() throws {
        let source = try chatComposerSource

        #expect(source.contains("struct CustomMenuButtonStyle: MenuStyle"))
        #expect(source.contains("Color.clear"))
        #expect(source.contains("ZStack {\n            Menu(configuration)"))
        #expect(source.contains("Icons.symbol(.add, size: theme.typography.heading)"))
        #expect(source.contains(".allowsHitTesting(false)"))
    }

    @Test("composer add button exposes platform-specific picker menus")
    func composerAddButtonExposesPlatformSpecificPickerMenus() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct ComposerAddMenu"))
        #expect(source.contains("Label(\"Files and Attach\""))
        #expect(source.contains("private struct ComposerOptionsMenuView"))
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
        #expect(source.contains("maxHeight: isExpandedPhoneLayout ? .infinity : Self.phoneFieldHeight"))
        #expect(source.contains(".frame(height: currentPanelHeight, alignment: .bottom)"))
    }

    @Test("phone composer expands on focus and exposes agent and model pickers")
    func phoneComposerExpandsOnFocusWithContextPickers() throws {
        let source = try chatComposerSource

        #expect(source.contains("@State private var isPhoneComposerExpanded = false"))
        #expect(source.contains("public static let expandedPhonePanelHeight: CGFloat = 228"))
        #expect(source.contains("onFocusChanged: updatePhoneComposerExpansion"))
        #expect(source.contains(".onChange(of: isTextFieldFocused)"))
        #expect(source.contains("private var isExpandedPhoneLayout: Bool"))
        #expect(source.contains("textFieldContainer(showsGlassBackground: !isExpandedPhoneLayout)"))
        #expect(!source.contains("private var expandedPhoneComposer: some View"))
        #expect(source.contains("MobileComposerAgentPicker("))
        #expect(source.contains("MobileComposerModelPicker("))
        #expect(source.contains("chat.composer.expanded"))
        #expect(source.contains("chat.composer.agent-picker"))
        #expect(source.contains("chat.composer.model-picker"))
        #expect(source.contains("if idiom != .phone"))
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

    @Test("composer always uses the currently selected chat view model")
    func composerUsesCurrentlySelectedChatViewModel() throws {
        let source = try chatComposerSource

        #expect(source.contains("private let viewModel: ChatScreenViewModel"))
        #expect(source.contains("self.viewModel = viewModel"))
        #expect(!source.contains("@State private var viewModel: ChatScreenViewModel"))
        #expect(!source.contains("State(initialValue: viewModel)"))
    }

    @Test("composer renders removable attachments and accepts clipboard files")
    func composerRendersAttachmentsAndAcceptsPaste() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct ChatComposerAttachmentStrip"))
        #expect(source.contains("viewModel.composerAttachments"))
        #expect(source.contains("remove: viewModel.removeComposerAttachment"))
        #expect(source.contains("onPasteCommand(of: [.fileURL, .image]"))
        #expect(source.contains("viewModel.attachItemProviders(providers)"))
        #expect(source.contains("MacAttachmentPasteMonitor(isEnabled: isTextFieldFocused)"))
        #expect(source.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown)"))
        #expect(source.contains("Self.isStandardPasteShortcut(event)"))
        #expect(source.contains("event.keyCode == 9"))
        #expect(source.contains("NSEvent.removeMonitor(eventMonitor)"))
        #expect(source.contains("NSPasteboard.general"))
        #expect(source.contains("pasteboard.data(forType: .png)"))
        #expect(source.contains("NSImage(pasteboard: pasteboard)"))
        #expect(source.contains("pasteAttachmentsFromSystemPasteboard()"))
        #expect(source.contains("private struct ChatComposerAttachmentPreview"))
        #expect(source.contains("Image(nsImage: image)"))
        #expect(source.contains("Image(systemName: \"xmark.circle.fill\")"))
        #expect(source.contains("HStack(alignment: .bottom, spacing: sp.s)"))
    }

    @Test("attachment-only drafts expose the send action")
    func attachmentOnlyDraftsCanSubmit() throws {
        let source = try chatComposerSource

        #expect(source.contains("trimmedDraftText.isEmpty && viewModel.composerAttachments.isEmpty"))
        #expect(source.contains("!trimmed.isEmpty || !viewModel.composerAttachments.isEmpty"))
    }

    @Test("composer text fields submit on enter")
    func composerTextFieldsSubmitOnEnter() throws {
        let source = try chatComposerSource

        #expect(source.contains(".submitLabel(.send)"))
        #expect(source.contains(".onSubmit {"))
    }

    @Test("shift return inserts a newline without submitting")
    func shiftReturnInsertsNewlineWithoutSubmitting() throws {
        let source = try chatComposerSource

        #expect(source.contains(".onKeyPress(.return, phases: .down) { keyPress in"))
        #expect(source.contains("keyPress.modifiers.contains(.shift)"))
        #expect(source.contains("selection: $draft.selection"))
        #expect(source.contains("insertNewlineAtSelection()\n                return .handled"))
        #expect(source.contains("draft.text.replaceSubrange(replacementRange, with: \"\\n\")"))
        #expect(source.contains("TextSelection(insertionPoint: insertionPoint)"))
        #expect(source.contains("@State private var composerCursorOffset: Int?"))
        #expect(source.contains("ChatComposerTextEdit.cursorOffsetAfterEdit("))
        #expect(!source.contains(".onChange(of: draft.selection)"))
    }

    @Test("composer wraps long text without reserving its maximum height")
    func composerTextFieldWrapsLongTextWithoutInflating() throws {
        let source = try chatComposerSource

        #expect(source.contains("axis: .vertical"))
        #expect(source.contains(".lineLimit(1...6)"))
        #expect(!source.contains("maximumPanelHeight"))
        #expect(source.contains("private static let panelRadius: CGFloat = panelHeight / 2"))
        #expect(source.contains("static let fieldHorizontalPadding: CGFloat = fieldHeight / 2"))
        #expect(source.contains("RoundedRectangle(cornerRadius: Self.panelRadius, style: .continuous)"))
        #expect(source.contains(".padding(.horizontal, Constants.fieldHorizontalPadding)"))
        #expect(source.contains(".padding(.vertical, sp.s)"))
    }

    @Test("long composer text stays bounded and scrolls vertically")
    func longComposerTextStaysBoundedAndScrollable() throws {
        let source = try chatComposerSource
        let fieldStart = try #require(source.range(of: "struct ChatTextField: View"))
        let dictationStart = try #require(source.range(of: "private struct DictationComposerBar"))
        let fieldSource = source[fieldStart.lowerBound..<dictationStart.lowerBound]

        #expect(!fieldSource.contains(".containerRelativeFrame(.horizontal)"))
        #expect(fieldSource.contains(".scrollIndicators(.visible, axes: .vertical)"))
        #expect(fieldSource.contains(".clipped()"))
        #expect(fieldSource.contains(".layoutPriority(1)"))
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
        let composerSource = try chatComposerSource
        let suggestionsSource = try composerSuggestionsSource

        #expect(suggestionsSource.contains("static let panelHeight: CGFloat = 320"))
        #expect(suggestionsSource.contains("minHeight: Self.panelHeight"))
        #expect(suggestionsSource.contains("maxHeight: Self.panelHeight"))
        #expect(composerSource.contains(".overlay(alignment: .top)"))
        #expect(composerSource.contains(".offset(y: -(ComposerSuggestionsView.panelHeight + autocompleteGap))"))
        #expect(!composerSource.contains(".alignmentGuide(.top)"))
        #expect(!composerSource.contains("composerSuggestionsOffset"))
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
        #expect(source.contains("guard (!trimmed.isEmpty || !viewModel.composerAttachments.isEmpty), viewModel.canSubmitMessage else { return }"))
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
        let dictationStart = try #require(source.range(of: "private struct DictationComposerBar"))
        let customTabStart = try #require(source.range(of: "fileprivate struct CustomTabItem"))
        let dictationSource = source[dictationStart.lowerBound..<customTabStart.lowerBound]

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
        #expect(!dictationSource.contains(".containerRelativeFrame(.horizontal)"))
    }

    @Test("desktop composer exposes a searchable model picker")
    func desktopComposerExposesSearchableModelPicker() throws {
        let source = try chatComposerSource

        #expect(source.contains("private struct ComposerOptionsMenuView"))
        #expect(source.contains("TextField(\"Search models\", text: $searchText)"))
        #expect(source.contains("groupedModels"))
        #expect(source.contains("selectedEffort.compactTitle"))
        #expect(source.contains("Constants.modelPickerRowHeight"))
        #expect(source.contains("Refresh Models"))
        #expect(source.contains("Edit Models…"))
        #expect(source.contains("chat.composer.model-picker"))
        #expect(source.contains("private struct ComposerMenuItem"))
        #expect(source.contains("private var selectedModelTitle: String"))
        #expect(source.contains(".popover(isPresented: $isPresented"))
    }
}
