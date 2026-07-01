import Foundation
import Testing

@Suite("ChatScreen rendering")
struct ChatScreenRenderingTests {
    private var chatScreenSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatScreen.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("root chat content delegates rendering to chat chrome and loads initial data on appear")
    func rootChatContentDelegatesRenderingToChatChrome() throws {
        let source = try chatScreenSource
        let contentStart = try #require(source.range(of: "private struct ChatScreenContent: View"))
        let chromeStart = try #require(source.range(of: "private struct ChatChrome: View"))
        let contentSource = source[contentStart.lowerBound..<chromeStart.lowerBound]

        #expect(contentSource.contains("ChatChrome("))
        #expect(contentSource.contains("ChatNavigationLeadingItems("))
        #expect(contentSource.contains("viewModel.loadInitialData()"))
    }

    @Test("phone navigation uses a dedicated mobile header capsule")
    func phoneNavigationUsesDedicatedMobileHeaderCapsule() throws {
        let source = try chatScreenSource

        #expect(source.contains("MobileChatNavigationHeader"))
        #expect(source.contains("MobileChatNavigationCenterCapsule"))
        #expect(source.contains("mobileNavigationCapsuleWidth"))
        #expect(source.contains("ChatOverlayLayout.pickerTopInset"))
        #expect(source.contains("effectiveSafeAreaTop: safeAreaInsets.top"))
        #expect(source.contains("Icons.symbol(.menu"))
    }

    @Test("empty mobile chat keeps composer pinned to bottom")
    func emptyMobileChatKeepsComposerPinnedToBottom() throws {
        let source = try chatScreenSource

        #expect(source.contains("let showsComposer = true"))
        #expect(source.contains("bottomClearance: composerScrollInset"))
        #expect(source.contains("Spacer(minLength: bottomClearance)"))
    }

    @Test("empty task draft surfaces the active context to the user")
    func emptyTaskDraftSurfacesTheActiveContextToTheUser() throws {
        let source = try chatScreenSource

        #expect(source.contains("if let activeContextTitle = viewModel.activeContextTitle"))
        #expect(source.contains("Text(activeContextTitle)"))
    }

    @Test("mobile navigation label shows the active context for drafts")
    func mobileNavigationLabelShowsTheActiveContextForDrafts() throws {
        let source = try chatScreenSource

        #expect(source.contains("viewModel.activeContextTitle ?? \"New chat\""))
    }

    @Test("agent selection in header uses picker view")
    func agentSelectionInHeaderUsesPickerView() throws {
        let source = try chatScreenSource

        #expect(source.contains("Picker(\"\", selection: selectedAgentId"))
        #expect(source.contains(".pickerStyle(.menu)"))
    }

    @Test("agent picker binding falls back to the first loaded agent id")
    func agentPickerBindingFallsBackToFirstLoadedAgentId() throws {
        let source = try chatScreenSource

        #expect(source.contains("viewModel.selectedAgent?.id"))
        #expect(source.contains("viewModel.agents.first?.id"))
        #expect(source.contains("?? \"\""))
    }
}
