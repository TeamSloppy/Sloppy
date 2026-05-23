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

@Test
func toolTranscriptCompactorShowsOnlyExecutingCalls() {
    let blocks: [SloppyTUITimelineBlock] = [
        .toolCall(tool: "files.read", reason: nil, summary: "Read README.md", details: nil),
        .toolResult(tool: "Read", rawTool: "files.read", ok: true, error: nil, durationMs: 3, details: nil),
        .toolCall(tool: "runtime.exec", reason: nil, summary: "swift test", details: nil),
        .toolCall(tool: "files.grep", reason: nil, summary: "Search TODO", details: nil),
        .toolResult(tool: "Grep", rawTool: "files.grep", ok: true, error: nil, durationMs: 8, details: nil),
    ]

    let visible = SloppyTUIToolTranscriptCompactor.visibleExecutingBlocks(in: blocks)

    #expect(visible.count == 1)
    guard case .toolCall(let tool, _, let summary, _) = visible.first else {
        Issue.record("only the in-flight call should stay visible")
        return
    }
    #expect(tool == "runtime.exec")
    #expect(summary == "swift test")
}

@Test
func toolTranscriptCompactorHidesCompletedCalls() {
    let blocks: [SloppyTUITimelineBlock] = [
        .toolCall(tool: "files.read", reason: nil, summary: "Read Package.swift", details: nil),
        .toolResult(tool: "Read", rawTool: "files.read", ok: true, error: nil, durationMs: 2, details: nil),
        .toolCall(tool: "files.grep", reason: nil, summary: "Search Sloppy", details: nil),
        .toolResult(tool: "Grep", rawTool: "files.grep", ok: true, error: nil, durationMs: 5, details: nil),
    ]

    let visible = SloppyTUIToolTranscriptCompactor.visibleExecutingBlocks(in: blocks)

    #expect(visible.isEmpty)
}
