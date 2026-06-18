import AgentRuntime
import Foundation
import Protocols
import Testing
import TauTUI
@testable import sloppy

@Test
func composerHighlightsSlashCommandsAndAtPaths() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/help /123_skill @Sources/sloppy/TUI/SloppyTUITheme.swift",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;103;232;249m"))
    #expect(highlighted[1].contains("\u{001B}[38;2;250;204;21m"))
    #expect(stripANSI(highlighted[1]) == lines[1])
}

@Test
func shellModeComposerBordersUseRedAccent() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "echo hello",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines, shellMode: true)

    #expect(highlighted[0].contains("\u{001B}[38;2;248;113;113m"))
    #expect(highlighted[2].contains("\u{001B}[38;2;248;113;113m"))
    #expect(stripANSI(highlighted[0]) == stripANSI(lines[0]))
    #expect(stripANSI(highlighted[2]) == stripANSI(lines[2]))
}

@Test
func shellModeMetaLineUsesRedShellTitle() {
    let line = SloppyTUITheme.composerShellMetaLine(
        width: 80,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        agent: "Yadev",
        provider: "openai"
    )

    #expect(stripANSI(line).contains("shell"))
    #expect(line.contains("\u{001B}[38;2;248;113;113m"))
    #expect(!line.contains("\u{001B}[38;2;251;178;123mshell"))
    #expect(VisibleWidth.measure(line) <= 80)
}

@Test
func runStatusLineIncludesTurnTokenUsage() {
    let status = AgentRunStatusEvent(
        stage: .responding,
        label: "Brewing",
        details: "Generating response...",
        tokenUsage: .init(prompt: 1_002, completion: 3_232)
    )

    let line = SloppyTUITheme.runStatusLine(status)

    #expect(line == "Brewing (1002 ↑ / 3232 ↓) - Generating response...")
}

@Test
func waitingIndicatorKeepsSpinnerBeforeWaitingWord() {
    let line = SloppyTUITheme.waitingIndicator(frame: 0, word: "recombobulating")

    #expect(stripANSI(line).hasPrefix("⠋ recombobulating"))
}

@Test
func waitingIndicatorIncludesTurnTokenUsageAfterWaitingWord() {
    let line = SloppyTUITheme.waitingIndicator(
        frame: 0,
        word: "recursing",
        tokenUsage: .init(prompt: 8_625, completion: 11)
    )

    #expect(stripANSI(line).hasPrefix("⠋ recursing (8625 ↑ / 11 ↓)"))
}

@Test
func composerContinuesAtPathHighlightAcrossWrappedLines() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "@/Users/vlad-prusakov/arcadia/mobile/yandex360/core/kmp/yx360-promozavr/promozavr/src/commonMain",
        "/kotlin/ru/yandex/disk/promozavr/PromozavrFlow.kt",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;250;204;21m"))
    #expect(highlighted[2].contains("\u{001B}[38;2;250;204;21m"))
    #expect(!highlighted[2].contains("\u{001B}[38;2;103;232;249m"))
    #expect(stripANSI(highlighted[1]) == lines[1])
    #expect(stripANSI(highlighted[2]) == lines[2])
}

@Test
func composerHighlightsPasteMarkersAndTaskReferences() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "Please inspect [paste #1 +12 lines] for #task-123",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;251;178;123m"))
    #expect(highlighted[1].contains("\u{001B}[38;2;74;222;128m"))
    #expect(stripANSI(highlighted[1]) == lines[1])
}

@Test
func composerDoesNotHighlightAutocompleteAfterEditorBorder() {
    let lines = [
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/help",
        "\u{001B}[38;2;82;211;194m────────\u{001B}[39m",
        "/model  Switch model",
    ]

    let highlighted = SloppyTUITheme.highlightedComposerLines(lines)

    #expect(highlighted[1].contains("\u{001B}[38;2;103;232;249m"))
    #expect(highlighted[3] == lines[3])
}

@Test
func userMessageHighlightsTaskReferences() {
    let lines = SloppyTUITheme.userMessageLines("Handle #task-123 with @Sources/sloppy/TUI", width: 80)
    let rendered = lines.joined(separator: "\n")

    #expect(rendered.contains("\u{001B}[38;2;74;222;128m"))
    #expect(rendered.contains("\u{001B}[38;2;250;204;21m"))
}

@Test
func normalizeTruncatesOverwideStyledLines() {
    let width = 32
    let line = "\u{001B}[38;2;250;204;21m" + String(repeating: "x", count: 96) + "\u{001B}[39m"

    let normalized = SloppyTUITheme.normalize(lines: [line], width: width, height: 1)

    #expect(normalized.count == 1)
    #expect(VisibleWidth.measure(normalized[0]) == width)
}

@Test
func toolLinesRenderMultilineFieldsAsSingleRows() {
    let width = 80
    let rows = [
        SloppyTUITheme.toolCallLine(
            tool: "runtime.exec",
            reason: "inspect\nthen run",
            summary: "bash -lc 'python3 - <<PY\nprint(1)\nPY'",
            width: width
        ),
        SloppyTUITheme.toolResultLine(
            tool: "runtime.exec",
            ok: false,
            error: "first line\nsecond line",
            durationMs: 12,
            width: width
        ),
    ]

    for row in rows {
        #expect(!stripANSI(row).contains("\n"))
        #expect(VisibleWidth.measure(row) <= width)
    }
}

@Test
func sessionListLinesFitCompactWidthAndSplitFooterHints() throws {
    let width = 36
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = [
        SloppyTUISessionListEntry(
            tracked: .init(
                agentId: "agent",
                sessionId: "session-compact-width",
                pinned: true,
                background: true,
                createdAt: now
            ),
            summary: AgentSessionSummary(
                id: "session-compact-width",
                agentId: "agent",
                title: String(repeating: "InvestigateSideView", count: 5),
                updatedAt: now,
                lastMessagePreview: String(repeating: "preview detail ", count: 12)
            ),
            section: .completed,
            detail: String(repeating: "long detail ", count: 12)
        ),
    ]

    let lines = SloppyTUITheme.sessionListLines(
        width: width,
        height: 12,
        entries: entries,
        selectedIndex: 0,
        projectName: String(repeating: "Project", count: 8),
        agentName: String(repeating: "Agent", count: 8)
    )
    let plain = lines.map(stripANSI)

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
    let selectedLine = try #require(lines.first { $0.contains("\u{001B}[48;2;251;178;123m") })
    #expect(selectedLine.contains("\u{001B}[38;2;0;0;0m"))
    #expect(!selectedLine.contains("\u{001B}[38;2;148;163;184m"))
    #expect(!selectedLine.contains("\u{001B}[38;2;74;222;128m"))
    #expect(plain.contains { $0.contains("type below to create") && $0.contains("enter to open") })
    #expect(plain.contains { $0.contains("space to reply") && $0.contains("ctrl+x") })
    #expect(!plain.contains { $0.contains("enter to open") && $0.contains("space to reply") })
}

@Test
func sidePaneZippingHonorsConfiguredWidths() throws {
    let rows = SloppyTUIScreen.zippedPaneLines(
        left: [
            "\u{001B}[38;2;250;204;21m" + String(repeating: "left-overflow", count: 12) + "\u{001B}[39m",
            "short",
        ],
        right: [
            String(repeating: "right-overflow", count: 12),
            "body",
        ],
        leftWidth: 37,
        rightWidth: 75,
        separator: "│",
        height: 3
    )

    #expect(rows.count == 3)
    for row in rows {
        #expect(VisibleWidth.measure(row) == 113)
    }

    let firstPlain = stripANSI(rows[0])
    let pieces = firstPlain.split(separator: "│", omittingEmptySubsequences: false)
    #expect(pieces.count == 2)
    let left = try #require(pieces.first)
    let right = try #require(pieces.last)
    #expect(left.count == 37)
    #expect(right.count == 75)
}

@Test
func chromeRowsFitNarrowTerminalWidth() {
    let width = 40
    let rows = [
        SloppyTUITheme.composerMetaLine(
            width: width,
            mode: .plan,
            model: "anthropic:claude-sonnet-4-6",
            agent: "Yadev",
            provider: "anthropic",
            tokenUsage: .init(
                promptTokens: 22_000,
                completionTokens: 13_000,
                totalTokens: 35_000,
                contextWindowTokens: 400_000,
                costUSD: 0.42
            )
        ),
        SloppyTUITheme.composerShellMetaLine(
            width: width,
            cwd: "/Users/vlad-prusakov/Developer/Sloppy/Sources/sloppy/TUI",
            agent: "Yadev",
            provider: "anthropic"
        ),
        SloppyTUITheme.interruptControlLine(width: width, frame: 3, isInterrupting: false),
        SloppyTUITheme.tokenUsageStatus(.init(
            promptTokens: 22_000,
            completionTokens: 13_000,
            totalTokens: 35_000,
            contextWindowTokens: 400_000,
            costUSD: 0.42
        )),
        SloppyTUITheme.tokenUsageFooterLine(
            width: width,
            summary: .init(
                promptTokens: 22_000,
                completionTokens: 13_000,
                totalTokens: 35_000,
                contextWindowTokens: 400_000,
                costUSD: 0.42
            )
        ),
        SloppyTUITheme.contextUsageProgressLine(
            width: width,
            summary: .init(
                promptTokens: 22_000,
                completionTokens: 13_000,
                totalTokens: 35_000,
                contextWindowTokens: 400_000,
                costUSD: 0.42
            )
        ),
        SloppyTUITheme.toolCallLine(
            tool: "runtime.exec",
            reason: String(repeating: "reason", count: 12),
            summary: String(repeating: "/Users/vlad-prusakov/Developer/Sloppy/", count: 4),
            width: width
        ),
        SloppyTUITheme.toolResultLine(
            tool: "runtime.exec",
            ok: false,
            error: String(repeating: "Rendered line exceeds width ", count: 6),
            durationMs: 123,
            width: width
        ),
        SloppyTUITheme.attachmentLine(
            name: String(repeating: "screenshot-", count: 10) + ".png",
            mimeType: "image/png",
            sizeBytes: 12_345,
            width: width
        ),
        SloppyTUITheme.toolOverflowLine(hiddenCount: 42, width: width),
        SloppyTUITheme.subSessionLine(
            title: String(repeating: "subagent-session-", count: 6),
            childSessionId: String(repeating: "abcdef", count: 6),
            status: .running("Reading files"),
            frame: 0,
            width: width
        ),
        SloppyTUITheme.transcriptHintLine(expanded: true, childSessionCount: 3, width: width),
    ]

    for row in rows {
        #expect(VisibleWidth.measure(row) <= width)
    }
}

@Test
func pickerSearchLineStylesSearchValueAndKeepsHeightStable() {
    let allItems = (0..<24).map { index in
        SloppyTUIPickerItem(
            value: "model-\(index)",
            label: "model-\(index)",
            description: "Model \(index)",
            isCurrent: index == 0,
            group: index < 12 ? "OpenAI" : "Provider \(index)"
        )
    }
    var picker = SloppyTUIPicker(
        kind: .model,
        title: "Select model",
        items: allItems,
        selectedIndex: 0,
        allItems: allItems,
        searchQuery: "model",
        supportsSearch: true
    )

    let firstPage = SloppyTUITheme.pickerLines(width: 100, picker: picker, maxVisible: 9)
    picker.selectedIndex = 18
    let laterPage = SloppyTUITheme.pickerLines(width: 100, picker: picker, maxVisible: 9)

    #expect(firstPage.count == laterPage.count)
    #expect(firstPage.joined(separator: "\n").contains("\u{001B}[38;2;103;232;249mmodel"))
}

@Test
func backgroundWrapAppliesThemeScreenBackground() {
    var theme = SloppyTUIResolvedTheme.default
    theme.screenBackground = SloppyTUIColor(red: 1, green: 2, blue: 3)
    SloppyTUITheme.apply(theme)
    defer { SloppyTUITheme.resetDefault() }

    let lines = SloppyTUITheme.screenBackgroundLines(["hello"], width: 10)

    #expect(lines[0].hasPrefix("\u{001B}[48;2;1;2;3m"))
    #expect(VisibleWidth.measure(lines[0]) == 10)
}

@Test
func operationStatusFooterRendersMultipleBusyStatuses() {
    let line = SloppyTUITheme.operationStatusFooterLine(
        width: 80,
        statuses: [
            SloppyTUIOperationStatus(kind: .indexing, label: "Indexing search", detail: "new project"),
            SloppyTUIOperationStatus(kind: .modelLoading, label: "Loading models", detail: "providers"),
        ],
        frame: 2
    )
    let plain = stripANSI(line)

    #expect(plain.contains("Indexing search"))
    #expect(plain.contains("Loading models"))
    #expect(VisibleWidth.measure(line) == 80)
}

@Test
func shimmeringTextUsesSkeletonPaletteInsteadOfRainbow() {
    let firstFrame = SloppyTUITheme.shimmeringText("brewing...", frame: 2)
    let laterFrame = SloppyTUITheme.shimmeringText("brewing...", frame: 5)

    #expect(stripANSI(firstFrame) == "brewing...")
    #expect(stripANSI(laterFrame) == "brewing...")
    #expect(VisibleWidth.measure(firstFrame) == 10)
    #expect(firstFrame != laterFrame)
    #expect(firstFrame.contains("\u{001B}[38;2;148;163;184m"))
    #expect(firstFrame.contains("\u{001B}[38;2;226;232;240m"))
    #expect(!firstFrame.contains("\u{001B}[38;2;248;113;113m"))
    #expect(!firstFrame.contains("\u{001B}[38;2;250;204;21m"))
    #expect(!firstFrame.contains("\u{001B}[38;2;74;222;128m"))
    #expect(!firstFrame.contains("\u{001B}[38;2;96;165;250m"))
}

@Test
func composerLayoutPlacesOperationStatusAboveInputLines() {
    let lines = SloppyTUIComposerLayout.lines(
        preInputLines: ["picker"],
        operationStatusLine: "Indexing search",
        inputLines: ["editor top", "editor body"],
        metaLines: ["Auto | model"],
        footerLine: "cwd"
    )

    #expect(lines == [
        "picker",
        "Indexing search",
        "editor top",
        "editor body",
        "Auto | model",
        "cwd",
    ])
}

@Test
func contextUsageProgressShowsFillPercentAndRemainingSpace() {
    let line = SloppyTUITheme.contextUsageProgressLine(
        width: 96,
        summary: .init(
            promptTokens: 80_000,
            completionTokens: 20_000,
            totalTokens: 100_000,
            contextWindowTokens: 400_000,
            costUSD: 1.25
        )
    )
    let plain = stripANSI(line)

    #expect(plain.contains("context [===---------]"))
    #expect(plain.contains("25%"))
    #expect(plain.contains("100.0K/400.0K tokens"))
    #expect(plain.contains("free 300.0K"))
    #expect(plain.contains("$1.25"))
    #expect(VisibleWidth.measure(line) <= 96)
}

@Test
func composerMetaLineShowsCompactContextIndicator() {
    let line = SloppyTUITheme.composerMetaLine(
        width: 120,
        mode: .build,
        model: "openai-api:gpt-5.5",
        agent: "Yadev",
        provider: "openai",
        tokenUsage: .init(
            promptTokens: 30_000,
            completionTokens: 8_000,
            totalTokens: 38_000,
            contextWindowTokens: 272_000,
            costUSD: nil
        ),
        runElapsed: 57,
        stageElapsed: 27
    )
    let plain = stripANSI(line)

    #expect(plain.contains("gpt-5.5"))
    #expect(plain.contains("ctx 38K/272K"))
    #expect(plain.contains("spent 38K"))
    #expect(plain.contains("[█░░░░░░░░░] 14%"))
    #expect(plain.contains("57s"))
    #expect(plain.contains("⏱ 27s"))
    #expect(!plain.contains("tokens:"))
    #expect(VisibleWidth.measure(line) <= 120)
}

@Test
func composerMetaLineSeparatesLastContextFromAggregateSpend() {
    let line = SloppyTUITheme.composerMetaLine(
        width: 120,
        mode: .auto,
        model: "gpt-5.5",
        agent: "Anton",
        provider: "openai",
        tokenUsage: .init(
            promptTokens: 40_962,
            completionTokens: 38,
            totalTokens: 41_000,
            contextWindowTokens: 272_000,
            costUSD: 3.22
        ),
        lastTurnTokenUsage: .init(prompt: 11_358, completion: 38)
    )
    let plain = stripANSI(line)

    #expect(plain.contains("ctx 11K/272K"))
    #expect(plain.contains("spent 41K"))
    #expect(!plain.contains("41K/272K"))
    #expect(VisibleWidth.measure(line) <= 120)
}

@Test
func composerMetaLineRendersAutoModeAsRainbowText() {
    let line = SloppyTUITheme.composerMetaLine(
        width: 120,
        mode: .auto,
        model: "openai-api:gpt-5.5",
        agent: "Yadev",
        provider: "openai"
    )

    #expect(stripANSI(line).contains("Auto"))
    #expect(line.contains("\u{001B}[38;2;248;113;113mA"))
    #expect(line.contains("\u{001B}[38;2;251;178;123mu"))
    #expect(line.contains("\u{001B}[38;2;250;204;21mt"))
    #expect(line.contains("\u{001B}[38;2;74;222;128mo"))
    #expect(VisibleWidth.measure(line) <= 120)
}

@Test
func exitSummaryRowsFitTerminalWidth() {
    let width = 64
    let lines = SloppyTUITheme.exitSummaryLines(
        .init(
            sessionID: "39c84dd2-5a21-44bb-ad2d-7bfef254b7ed",
            canResume: true,
            toolCallCount: 3,
            successfulToolCallCount: 2,
            failedToolCallCount: 1,
            wallTime: 19.7,
            agentActiveTime: 12.4,
            apiTime: 10.0,
            toolTime: 2.4
        ),
        width: width
    )
    let plain = lines.map(stripANSI).joined(separator: "\n")

    #expect(plain.contains("Interaction Summary"))
    #expect(plain.contains("Tool Calls:"))
    #expect(plain.contains("sloppy -s"))
    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func quickReferenceRendersWideMulticolumnLayout() {
    let width = 120
    let lines = SloppyTUITheme.quickReferenceLines(width: width)
    let plain = lines.map(stripANSI)

    #expect(plain.first == "## Quick reference")
    #expect(plain.joined(separator: "\n").contains("`!` shell mode"))
    #expect(plain.joined(separator: "\n").contains("`Option+P` model picker"))
    #expect(plain.joined(separator: "\n").contains("`Ctrl+T` project tasks"))
    #expect(plain.joined(separator: "\n").contains("`Ctrl+G` newest subagent"))
    #expect(plain.joined(separator: "\n").contains("`/` commands"))
    #expect(plain.joined(separator: "\n").contains("`#` project tasks"))

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func quickReferenceRendersNarrowSingleColumnLayout() {
    let width = 34
    let lines = SloppyTUITheme.quickReferenceLines(width: width)
    let plain = lines.map(stripANSI)

    #expect(plain.contains("- `/` commands"))
    #expect(plain.contains("- `Option+R` redo turn"))
    #expect(!plain.contains { $0.contains("  `") })

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func reasoningEffortSliderRendersSelectionAndFitsWidth() {
    let width = 72
    let lines = SloppyTUITheme.reasoningEffortSliderLines(
        width: width,
        efforts: SloppyTUIReasoningEffortSelector.options,
        selectedIndex: SloppyTUIReasoningEffortSelector.index(for: .medium)
    )
    let plain = lines.map(stripANSI).joined(separator: "\n")

    #expect(plain.contains("Speed"))
    #expect(plain.contains("Intelligence"))
    #expect(plain.contains("low"))
    #expect(plain.contains("medium"))
    #expect(plain.contains("high"))
    #expect(plain.contains("Enter to confirm"))

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func reasoningEffortSelectorDefaultsToMediumAndClampsMovement() {
    #expect(SloppyTUIReasoningEffortSelector.index(for: nil) == SloppyTUIReasoningEffortSelector.index(for: .medium))
    #expect(SloppyTUIReasoningEffortSelector.effort(at: -10) == .low)
    #expect(SloppyTUIReasoningEffortSelector.effort(at: 10) == .high)
    #expect(SloppyTUIReasoningEffortSelector.movedIndex(from: 0, delta: -1) == 0)
    #expect(SloppyTUIReasoningEffortSelector.movedIndex(from: 2, delta: 1) == 2)
}

@Test
func contextUsageMarkdownShowsReadableTokenBreakdown() {
    let markdown = SloppyTUITheme.contextUsageMarkdown(.init(
        modelTitle: "Claude Opus 4.7",
        modelID: "claude-opus-4-7",
        contextWindowLabel: "1M",
        promptTokens: 6_000,
        completionTokens: 2_000,
        totalTokens: 8_000,
        contextWindowTokens: 1_000_000,
        pendingContextAttached: true,
        pendingUploadCount: 2
    ))

    let plainMarkdown = stripANSI(markdown)
    #expect(markdown.contains("## Context Usage"))
    #expect(plainMarkdown.contains("Claude Opus 4.7 · 8.0K/1m tokens"))
    #expect(plainMarkdown.contains("claude-opus-4-7 · 1M context"))
    #expect(plainMarkdown.contains("used 1% · free 992.0K tokens"))
    #expect(plainMarkdown.contains("Context window"))
    #expect(plainMarkdown.contains("No context ledger yet; using token usage fallback."))
    #expect(plainMarkdown.contains("Last turn"))
    #expect(plainMarkdown.contains("- Cached input: 0 tokens"))
    #expect(plainMarkdown.contains("- Uncached input: 0 tokens"))
    #expect(plainMarkdown.contains("● Input prompt:  6.0K tokens (0.6%)"))
    #expect(plainMarkdown.contains("● Completion: 2.0K tokens (0.2%)"))
    #expect(plainMarkdown.contains("□ Free space: 992.0K tokens"))
    #expect(!plainMarkdown.contains("Estimated usage by category"))
    #expect(plainMarkdown.contains("□ □ □ □ □ □ □ □ □ □"))
    #expect(plainMarkdown.contains("Pending next-message context: yes"))
    #expect(plainMarkdown.contains("Pending uploads: 2"))
    #expect(plainMarkdown.contains("/context changes"))
    #expect(plainMarkdown.contains("/context diff"))
}

@Test
func contextUsageMarkdownSeparatesWindowAndLastTurnEconomics() {
    let summary = SloppyTUIContextUsageSummary(
        modelTitle: "GPT Test",
        modelID: "openai-oauth:gpt-test",
        contextWindowLabel: "10K",
        promptTokens: 3_700,
        completionTokens: 80,
        totalTokens: 3_780,
        contextWindowTokens: 10_000,
        pendingContextAttached: false,
        pendingUploadCount: 0,
        ledgerCategories: [
            .init(label: "Bootstrap", tokens: 2_000),
            .init(label: "Tools", tokens: 1_500),
            .init(label: "Current turn", tokens: 100),
        ],
        lastTurnInputTokens: 3_700,
        lastTurnCachedInputTokens: 3_000,
        lastTurnUncachedInputTokens: 700,
        lastTurnCacheCreationInputTokens: 400,
        lastTurnCompletionTokens: 80,
        lastTurnReasoningTokens: 12
    )

    let markdown = SloppyTUITheme.contextUsageMarkdown(summary)
    let plainMarkdown = stripANSI(markdown)
    #expect(plainMarkdown.contains("Context window"))
    #expect(plainMarkdown.contains("- Bootstrap: 2.0K tokens"))
    #expect(plainMarkdown.contains("- Tools: 1.5K tokens"))
    #expect(plainMarkdown.contains("- Current turn: 100 tokens"))
    #expect(plainMarkdown.contains("Last turn"))
    #expect(plainMarkdown.contains("- Input: 3.7K tokens"))
    #expect(plainMarkdown.contains("- Cached input: 3.0K tokens"))
    #expect(plainMarkdown.contains("- Uncached input: 700 tokens"))
    #expect(plainMarkdown.contains("- Cache creation: 400 tokens"))
    #expect(plainMarkdown.contains("- Output: 80 tokens"))
    #expect(plainMarkdown.contains("- Reasoning: 12 tokens"))
}

@Test
func contextUsageSummaryPrefersLedgerOverAggregateTokenUsageAndFallsBackWithoutIt() {
    let usage = TokenUsageResponse(
        items: [],
        totalPromptTokens: 9_500,
        totalCompletionTokens: 220,
        totalTokens: 9_720,
        totalCachedInputTokens: 700,
        totalCacheCreationInputTokens: 120,
        totalReasoningTokens: 33
    )
    let ledger = ContextLedgerSnapshot(
        channelId: "agent:test:session:test",
        contextWindowTokens: 32_000,
        reservedOutputTokens: 1_000,
        entries: [
            .init(category: .bootstrapStatic, label: "Bootstrap", estimatedTokens: 2_000),
            .init(category: .toolResults, label: "Tool results", estimatedTokens: 1_600),
        ],
        lastTurnUsage: .init(
            prompt: 3_600,
            completion: 180,
            cachedInputTokens: 2_400,
            cacheCreationInputTokens: 300,
            reasoningTokens: 44
        )
    )

    let preferredSummary = SloppyTUIContextUsageSummaryBuilder.makeSummary(
        modelTitle: "GPT Test",
        modelID: "openai:gpt-test",
        contextWindowLabel: "32K",
        contextWindowTokens: 32_000,
        usage: usage,
        ledger: ledger,
        pendingContextAttached: true,
        pendingUploadCount: 2
    )

    #expect(preferredSummary.promptTokens == 3_600)
    #expect(preferredSummary.totalTokens == 3_600)
    #expect(preferredSummary.ledgerCategories == [
        .init(label: "bootstrap_static", tokens: 2_000),
        .init(label: "tool_results", tokens: 1_600),
    ])
    #expect(preferredSummary.lastTurnInputTokens == 3_600)
    #expect(preferredSummary.lastTurnCachedInputTokens == 2_400)
    #expect(preferredSummary.lastTurnUncachedInputTokens == 1_200)
    #expect(preferredSummary.lastTurnCacheCreationInputTokens == 300)
    #expect(preferredSummary.lastTurnCompletionTokens == 180)
    #expect(preferredSummary.lastTurnReasoningTokens == 44)

    let fallbackSummary = SloppyTUIContextUsageSummaryBuilder.makeSummary(
        modelTitle: "GPT Test",
        modelID: "openai:gpt-test",
        contextWindowLabel: "32K",
        contextWindowTokens: 32_000,
        usage: usage,
        ledger: nil,
        pendingContextAttached: false,
        pendingUploadCount: 0
    )

    #expect(fallbackSummary.promptTokens == 9_500)
    #expect(fallbackSummary.totalTokens == 9_720)
    #expect(fallbackSummary.ledgerCategories.isEmpty)
    #expect(fallbackSummary.lastTurnInputTokens == 0)
    #expect(fallbackSummary.lastTurnCachedInputTokens == 0)
    #expect(fallbackSummary.lastTurnUncachedInputTokens == 0)
    #expect(fallbackSummary.lastTurnCacheCreationInputTokens == 0)
    #expect(fallbackSummary.lastTurnCompletionTokens == 0)
    #expect(fallbackSummary.lastTurnReasoningTokens == 0)
}

@Test
func defaultSessionStatusAvoidsComposerMetadataDuplication() {
    let status = stripANSI(SloppyTUITheme.sessionStatusLine(
        context: "  queue: 1 ctrl+b cancel",
        attachments: "",
        sessionID: "session-abcdef123456"
    ))

    #expect(!status.contains("mode:"))
    #expect(!status.contains("model:"))
    #expect(status.contains("queue: 1"))
    #expect(status.contains("last:"))
}

@Test
func noticeToastLinesRenderCenteredPopupAndStayWidthBounded() {
    let lines = SloppyTUITheme.noticeToastLines(
        "Copied selection to clipboard with a bit of extra detail",
        width: 48
    )
    let plain = lines.map(stripANSI)

    #expect(lines.count == 3)
    #expect(plain[1].contains("Copied selection"))
    #expect(plain[1].contains("▌"))
    #expect(plain[1].contains("▐"))
    for line in lines {
        #expect(VisibleWidth.measure(line) <= 48)
    }
}

@Test
func backgroundBlocksIncludeBreathingRoom() {
    let width = 40
    let lines = SloppyTUITheme.userMessageLines("hello", width: width)

    #expect(lines.count == 3)
    #expect(stripANSI(lines[0]).trimmingCharacters(in: .whitespaces).isEmpty)
    #expect(stripANSI(lines[1]).hasPrefix("  › hello"))
    #expect(stripANSI(lines[2]).trimmingCharacters(in: .whitespaces).isEmpty)

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func buildProgressRendersStructuredWrappedLines() {
    let width = 56
    let progress = AgentBuildProgressEvent(
        title: "Project picker UI changes",
        items: [
            AgentBuildProgressItem(
                id: "inspect",
                title: "Inspect project structure and current project picker UI",
                status: .done,
                definitionOfDone: "Locate relevant window/view code, tests, and build commands.",
                details: "Found ProjectOpeningView and layout tests."
            ),
            AgentBuildProgressItem(
                id: "verify",
                title: "Verify",
                status: .inProgress,
                definitionOfDone: "Run smallest relevant tests and final project build successfully."
            ),
        ]
    )

    let lines = SloppyTUITheme.buildProgressLines(progress, width: width)
    let plain = lines.map(stripANSI)

    #expect(plain[0].trimmingCharacters(in: .whitespaces) == "Project picker UI changes")
    #expect(plain.contains { $0.hasPrefix("  [x] Inspect project structure") })
    #expect(plain.contains { $0.hasPrefix("      ") && $0.contains("UI") })
    #expect(plain.contains { $0.hasPrefix("      DoD: Locate relevant") })
    #expect(plain.contains { $0.hasPrefix("      Notes: Found ProjectOpeningView") })
    #expect(plain.contains { $0.hasPrefix("  [~] Verify") })
    #expect(!plain.joined(separator: "\n").contains("UI - DoD:"))

    for line in lines {
        #expect(VisibleWidth.measure(line) <= width)
    }
}

@Test
func buildProgressColorsItemsByStatus() {
    let progress = AgentBuildProgressEvent(
        title: "Build progress",
        items: [
            AgentBuildProgressItem(id: "done", title: "Done item", status: .done, definitionOfDone: "Complete."),
            AgentBuildProgressItem(id: "active", title: "Active item", status: .inProgress, definitionOfDone: "Working."),
            AgentBuildProgressItem(id: "pending", title: "Pending item", status: .pending, definitionOfDone: "Queued."),
        ]
    )

    let rendered = SloppyTUITheme.buildProgressLines(progress, width: 80).joined(separator: "\n")

    #expect(rendered.contains("\u{001B}[38;2;74;222;128m"))
    #expect(rendered.contains("\u{001B}[38;2;251;178;123m"))
    #expect(rendered.contains("\u{001B}[38;2;148;163;184m"))
}

@Test
func welcomeScreenShowsSingleTip() {
    let lines = SloppyTUITheme.welcomeScreen(
        width: 120,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        project: "Sloppy",
        agent: "sloppy",
        model: "openai-api:gpt-5-codex-mini",
        mode: .build,
        includeFooter: false
    )

    let tipLines = lines.filter { stripANSI($0).contains("Tip  ") }

    #expect(tipLines.count == 1)
}

@Test
func welcomeIntroBlockIsCenteredUnderLogo() throws {
    let width = 120
    let lines = SloppyTUITheme.welcomeScreen(
        width: width,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        project: "Sloppy",
        agent: "sloppy",
        model: "openai-api:gpt-5-codex-mini",
        mode: .build,
        includeFooter: false
    )

    let promptLine = try #require(lines.first { stripANSI($0).contains("Ask anything") })

    #expect(leadingSpaceCount(stripANSI(promptLine)) == 28)
}

@Test
func elapsedFormatsShortAndLongRuns() {
    #expect(SloppyTUITheme.elapsed(0) == "00:00")
    #expect(SloppyTUITheme.elapsed(65) == "01:05")
    #expect(SloppyTUITheme.elapsed(3_661) == "1:01:01")
}

@Test
func shortIDStripsSessionPrefixBeforeTruncating() {
    #expect(SloppyTUITheme.shortID("session-abcdef123456") == "abcdef12")
}

@Test
func sessionDisplayTitleUsesPreviewForDefaultDashboardStyleTitles() {
    let session = AgentSessionSummary(
        id: "session-abcdef123456",
        agentId: "sloppy",
        title: "Session session-",
        messageCount: 2,
        lastMessagePreview: "Refactor the TUI session header"
    )

    #expect(SloppyTUITheme.sessionDisplayTitle(session) == "Refactor the TUI session header")
    #expect(SloppyTUITheme.sessionHeaderTitle(session).contains("Refactor the TUI session header"))
    #expect(SloppyTUITheme.sessionHeaderTitle(session).contains("(abcdef12)"))
}

@Test
func terminalTitleUsesStatusAndDisplaySessionTitle() {
    let session = AgentSessionSummary(
        id: "session-abcdef123456",
        agentId: "sloppy",
        title: "Session session-",
        messageCount: 2,
        lastMessagePreview: "Refactor the TUI session header"
    )

    let title = SloppyTUITheme.terminalTitle(status: "responding", session: session, agent: "SLOPPY")

    #expect(title == "Sloppy - responding - Refactor the TUI session header - SLOPPY")
}

@Test
func terminalTitleEscapeStripsControlCharacters() {
    let escaped = SloppyTUITheme.terminalTitleEscape("Sloppy\u{001B}]0;bad\u{0007}\nTitle")

    #expect(escaped == "\u{001B}]0;Sloppy]0;badTitle\u{0007}")
}

@Test
func sessionDisplayTitleUsesPreviewForLegacyTUIChatTitles() {
    let session = AgentSessionSummary(
        id: "session-abcdef123456",
        agentId: "sloppy",
        title: "TUI chat",
        messageCount: 2,
        lastMessagePreview: "Investigate absolute path submission"
    )

    #expect(SloppyTUITheme.sessionDisplayTitle(session) == "Investigate absolute path submission")
}

@Test
func sessionDisplayTitleKeepsSpecificTitles() {
    let session = AgentSessionSummary(
        id: "session-abcdef123456",
        agentId: "sloppy",
        title: "Fork: improve project overlay",
        messageCount: 2,
        lastMessagePreview: "Something else"
    )

    #expect(SloppyTUITheme.sessionDisplayTitle(session) == "Fork: improve project overlay")
}

@Test
func appFooterShowsMCPAvailabilitySummary() {
    let greenFooter = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        mcpSummary: SloppyTUIMCPStatusSummary(available: 3, total: 3)
    )
    let yellowFooter = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        mcpSummary: SloppyTUIMCPStatusSummary(available: 1, total: 3)
    )
    let redFooter = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        mcpSummary: SloppyTUIMCPStatusSummary(available: 0, total: 3)
    )
    let grayFooter = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        mcpSummary: .empty
    )

    #expect(stripANSI(greenFooter).contains("3/3 MCPs"))
    #expect(greenFooter.contains("\u{001B}[38;2;74;222;128m"))
    #expect(stripANSI(yellowFooter).contains("1/3 MCPs"))
    #expect(yellowFooter.contains("\u{001B}[38;2;250;204;21m"))
    #expect(stripANSI(redFooter).contains("0/3 MCPs"))
    #expect(redFooter.contains("\u{001B}[38;2;248;113;113m"))
    #expect(stripANSI(grayFooter).contains("0 MCPs"))
    #expect(grayFooter.contains("\u{001B}[38;2;148;163;184m"))
}

@Test
func appFooterShowsProjectSourceControlStatus() {
    let footer = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        sourceControl: SloppyTUISourceControlFooterStatus(
            providerId: "git-cli",
            isRepository: true,
            branch: "main",
            linesAdded: 12,
            linesDeleted: 3
        )
    )
    let plain = stripANSI(footer)

    #expect(plain.contains("git main +12 -3"))
    #expect(!plain.contains("dev build"))
}

@Test
func appFooterUsesConfiguredSourceControlProviderLabel() {
    let footer = SloppyTUITheme.appFooter(
        width: 100,
        cwd: "/Users/vlad-prusakov/Developer/Sloppy",
        sourceControl: SloppyTUISourceControlFooterStatus(
            providerId: "jj",
            isRepository: true,
            branch: "feature/runtime"
        )
    )

    #expect(stripANSI(footer).contains("jj feature/runtime"))
}

@Test
func mcpStatusLineIsCompactForMultilineErrors() {
    let status = MCPServerStatus(
        id: "claude-mobile",
        transport: "stdio",
        enabled: true,
        connected: false,
        exposeTools: true,
        exposeResources: false,
        exposePrompts: false,
        toolPrefix: "mobile",
        message: """
        Claude Mobile MCP server running

        Client detected: unknown (sloppy v1.0.0)

        Options:
          --help Show help
        """
    )

    let line = SloppyTUITheme.mcpStatusLine(status)

    #expect(line.contains("`claude-mobile`"))
    #expect(line.contains("unavailable"))
    #expect(line.contains("prefix mobile"))
    #expect(line.contains("Claude Mobile MCP server running"))
    #expect(!line.contains("Options:"))
    #expect(!line.contains("\n"))
}

@Test
func tuiThemeStoreLoadsCustomThemeWithPartialDefaults() throws {
    let root = try makeThemeTestWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }
    let themes = root.appendingPathComponent("tui/themes", isDirectory: true)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try Data("""
    {
      "name": "Forest",
      "colors": {
        "accent": "#34d399",
        "panelBackground": "#111827"
      }
    }
    """.utf8).write(to: themes.appendingPathComponent("forest.json"))

    let catalog = SloppyTUIThemeStore(workspaceRoot: root).loadCatalog()
    let theme = try #require(catalog.theme(id: "custom:forest"))

    #expect(catalog.warnings.isEmpty)
    #expect(theme.name == "Forest")
    #expect(theme.source == "forest.json")
    #expect(theme.accent == SloppyTUIColor(red: 52, green: 211, blue: 153))
    #expect(theme.panelBackground == SloppyTUIColor(red: 17, green: 24, blue: 39))
    #expect(theme.foreground == SloppyTUIResolvedTheme.default.foreground)
}

@Test
func tuiThemeStoreSkipsInvalidThemeFiles() throws {
    let root = try makeThemeTestWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }
    let themes = root.appendingPathComponent("tui/themes", isDirectory: true)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try Data(#"{"colors":{"accent":"not-a-color"}}"#.utf8)
        .write(to: themes.appendingPathComponent("bad-color.json"))
    try Data(#"{"colors":"oops"}"#.utf8)
        .write(to: themes.appendingPathComponent("malformed.json"))

    let catalog = SloppyTUIThemeStore(workspaceRoot: root).loadCatalog()

    #expect(catalog.themes.map(\.id) == ["default"])
    #expect(catalog.warnings.count == 2)
    #expect(catalog.warnings.contains { $0.fileName == "bad-color.json" })
    #expect(catalog.warnings.contains { $0.fileName == "malformed.json" })
}

@Test
func tuiThemeStoreUsesCustomPrefixForDuplicateSafeIDs() throws {
    let root = try makeThemeTestWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }
    let themes = root.appendingPathComponent("tui/themes", isDirectory: true)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try Data(##"{"name":"Custom Default","colors":{"accent":"#ffffff"}}"##.utf8)
        .write(to: themes.appendingPathComponent("default.json"))

    let catalog = SloppyTUIThemeStore(workspaceRoot: root).loadCatalog()

    #expect(catalog.theme(id: "default")?.source == "built-in")
    #expect(catalog.theme(id: "custom:default")?.name == "Custom Default")
}

@Test
func tuiThemeStoreSeedsOpenCodeThemeWithoutOverwriting() throws {
    let root = try makeThemeTestWorkspace()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SloppyTUIThemeStore(workspaceRoot: root)

    try store.ensureSeedThemes()
    let themeURL = store.themesURL.appendingPathComponent(SloppyTUIThemeStore.opencodeThemeFileName)
    let firstPayload = try String(contentsOf: themeURL, encoding: .utf8)
    let catalog = store.loadCatalog()
    let theme = try #require(catalog.theme(id: "custom:opencode"))

    #expect(firstPayload.contains(#""name": "OpenCode""#))
    #expect(theme.name == "OpenCode")
    #expect(theme.source == "opencode.json")
    #expect(theme.accent == SloppyTUIColor(red: 120, green: 220, blue: 232))
    #expect(theme.panelBackground == SloppyTUIColor(red: 0, green: 0, blue: 0))
    #expect(theme.thinkingBackground == SloppyTUIColor(red: 0, green: 0, blue: 0))
    #expect(theme.textBackground == SloppyTUIColor(red: 0, green: 0, blue: 0))
    #expect(theme.truncatedBackground == SloppyTUIColor(red: 0, green: 0, blue: 0))

    try Data(##"{"name":"Mine","colors":{"accent":"#ffffff"}}"##.utf8).write(to: themeURL)
    try store.ensureSeedThemes()
    let secondPayload = try String(contentsOf: themeURL, encoding: .utf8)
    #expect(secondPayload.contains(#""name":"Mine""#))
}

@Test
func tuiThemeRolesRenderAnsiAndDefaultThemeStaysStable() {
    var theme = SloppyTUIResolvedTheme.default
    theme.id = "custom:test"
    theme.name = "Test"
    theme.source = "test.json"
    theme.accentBright = SloppyTUIColor(red: 1, green: 2, blue: 3)
    theme.foreground = SloppyTUIColor(red: 4, green: 5, blue: 6)
    theme.muted = SloppyTUIColor(red: 7, green: 8, blue: 9)
    theme.userMessageBackground = SloppyTUIColor(red: 10, green: 11, blue: 12)

    let styled = theme.accentBright.foregroundStyle("title")
        + theme.foreground.foregroundStyle("body")
        + theme.muted.foregroundStyle("muted")
    let background = AnsiWrapping.applyBackgroundToLine(
        "x",
        width: 1,
        background: theme.userMessageBackground.background
    )

    #expect(styled.contains("\u{001B}[38;2;1;2;3m"))
    #expect(styled.contains("\u{001B}[38;2;4;5;6m"))
    #expect(styled.contains("\u{001B}[38;2;7;8;9m"))
    #expect(background.contains("\u{001B}[48;2;10;11;12m"))

    SloppyTUITheme.resetDefault()
    let defaultHeader = SloppyTUITheme.header(project: "Project", agent: "Agent", session: "Session")
    #expect(defaultHeader.contains("\u{001B}[38;2;103;232;249m"))
}

private func makeThemeTestWorkspace() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-tui-theme-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func leadingSpaceCount(_ line: String) -> Int {
    line.prefix { $0 == " " }.count
}

private func stripANSI(_ line: String) -> String {
    var result = ""
    var index = line.startIndex
    while index < line.endIndex {
        if line[index] == "\u{001B}" {
            index = ansiEscapeEnd(in: line, from: index)
            continue
        }
        result.append(line[index])
        index = line.index(after: index)
    }
    return result
}

private func ansiEscapeEnd(in line: String, from start: String.Index) -> String.Index {
    let next = line.index(after: start)
    guard next < line.endIndex else {
        return next
    }

    if line[next] == "[" {
        var index = line.index(after: next)
        while index < line.endIndex {
            let scalar = line[index].unicodeScalars.first?.value ?? 0
            index = line.index(after: index)
            if scalar >= 0x40 && scalar <= 0x7E {
                return index
            }
        }
        return line.endIndex
    }

    return line.index(after: next)
}
