import Testing
@testable import sloppy

@Test
func chatTimelineCompositionPlacesWorkspaceDiffInsideChatBeforeEphemeralCards() {
    let diffPreview = SloppyTUIWorkspaceDiffPreview(
        branch: "main",
        linesAdded: 12,
        linesDeleted: 3,
        diff: "diff --git a/App.swift b/App.swift\n+hello",
        truncated: false
    )
    let blocks = SloppyTUIChatTimelineComposition.blocks(
        sessionBlocks: [.message(role: .user, text: "please fix")],
        liveAssistantBlocks: [.message(role: .assistant, text: "done")],
        queuedMessageBlocks: [.local("queued placeholder")],
        workspaceDiffPreview: diffPreview,
        localCards: [SloppyTUILocalCard(id: 1, block: .local("notice"))]
    )

    #expect(blocks.count == 5)
    guard case .message(.user, "please fix") = blocks[0] else {
        Issue.record("session chat should stay first")
        return
    }
    guard case .workspaceDiff(let branch, let added, let deleted, let diff, let truncated) = blocks[1] else {
        Issue.record("workspace diff should be part of the chat timeline, before dynamic/local cards")
        return
    }
    #expect(branch == "main")
    #expect(added == 12)
    #expect(deleted == 3)
    #expect(diff.contains("+hello"))
    #expect(truncated == false)
    guard case .message(.assistant, "done") = blocks[2] else {
        Issue.record("live assistant message should remain in the timeline after the diff preview")
        return
    }
    guard case .local("notice") = blocks[4] else {
        Issue.record("local cards should remain last and no longer own the auto diff preview")
        return
    }
}

@Test
func chatTimelineCompositionOmitsWorkspaceDiffWhenPreviewIsNil() {
    let blocks = SloppyTUIChatTimelineComposition.blocks(
        sessionBlocks: [.message(role: .user, text: "hello")],
        liveAssistantBlocks: [],
        queuedMessageBlocks: [],
        workspaceDiffPreview: nil,
        localCards: [SloppyTUILocalCard(id: 1, block: .local("notice"))]
    )

    #expect(blocks.count == 2)
    #expect(!blocks.contains { block in
        if case .workspaceDiff = block { return true }
        return false
    })
}
