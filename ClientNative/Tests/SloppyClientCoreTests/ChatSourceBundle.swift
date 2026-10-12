import Foundation

/// Large chat sources are split across several files. Source-level tests assert on
/// a type's whole implementation, so reading its root file also returns the files
/// that were split out of it, in their original source order.
private struct ChatSplitSource {
    var before: [String] = []
    var after: [String]
}

private let chatSplitSourceFiles: [String: ChatSplitSource] = [
    "ChatScreenViewModel.swift": ChatSplitSource(
        before: [
            "ChatComposerTypes.swift", "ChatStreamingSupport.swift", "ChatMessageQueue.swift",
            "ChatTranscriptState.swift", "ChatStreamDeliveryState.swift",
        ],
        after: [
            "ChatScreenViewModel+Composer.swift", "ChatScreenViewModel+SessionCatalog.swift",
            "ChatScreenViewModel+Selection.swift", "ChatScreenViewModel+SessionManagement.swift",
            "ChatScreenViewModel+Attachments.swift", "ChatScreenViewModel+Navigation.swift",
            "ChatScreenViewModel+Connection.swift", "ChatScreenViewModel+RunState.swift",
            "ChatScreenViewModel+SessionSummaries.swift", "ChatScreenViewModel+Sending.swift",
            "ChatScreenViewModel+ToolApproval.swift", "ChatScreenViewModel+Voice.swift",
            "ChatScreenViewModel+Models.swift", "ChatScreenViewModel+ComposerDrafts.swift",
        ]
    ),
    "ChatScreen.swift": ChatSplitSource(after: [
        "ChatScreenAttachmentPickers.swift", "ChatScreenToolbars.swift", "ChatChrome.swift",
        "ChatTranscriptRegions.swift", "ChatComposerOverlay.swift", "ChatApprovalCards.swift",
        "ChatTranscriptPane.swift",
    ]),
    "ChatBubbleView.swift": ChatSplitSource(after: [
        "ChatSystemMessages.swift", "ChatThinkingIndicator.swift", "ChatSegmentViews.swift",
    ]),
    "ChatComposerView.swift": ChatSplitSource(after: [
        "ChatComposerToolbarMenus.swift", "ChatComposerOptionsMenu.swift",
        "ChatComposerMobilePickers.swift", "ChatTextField.swift",
        "ChatComposerAttachmentViews.swift", "ChatComposerDictationBar.swift",
        "ChatComposerButtons.swift",
    ]),
    "ChatNativeTextEditor.swift": ChatSplitSource(after: [
        "ChatUIKitComposerTextEditor.swift", "ChatAppKitComposerTextEditor.swift",
    ]),
    "ChatNativeTranscriptView.swift": ChatSplitSource(after: [
        "ChatUIKitTranscriptCollection.swift", "ChatAppKitTranscriptCollection.swift",
        "AppKitChatTranscriptLayout.swift", "AppKitHostedTranscriptItem.swift",
    ]),
]

extension String {
    init(chatSourceContentsOf url: URL, encoding: String.Encoding) throws {
        let text = try String(contentsOf: url, encoding: encoding)
        guard let split = chatSplitSourceFiles[url.lastPathComponent] else {
            self = text
            return
        }
        var chatRoot = url.deletingLastPathComponent()
        while chatRoot.lastPathComponent != "Chat", chatRoot.pathComponents.count > 1 {
            chatRoot.deleteLastPathComponent()
        }
        var urlsByName: [String: URL] = [:]
        if let enumerator = FileManager.default.enumerator(at: chatRoot, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                urlsByName[fileURL.lastPathComponent] = fileURL
            }
        }
        func contents(of names: [String]) throws -> [String] {
            try names.compactMap { urlsByName[$0] }.map { try String(contentsOf: $0, encoding: encoding) }
        }
        self = (try contents(of: split.before) + [text] + contents(of: split.after)).joined(separator: "\n")
    }
}
