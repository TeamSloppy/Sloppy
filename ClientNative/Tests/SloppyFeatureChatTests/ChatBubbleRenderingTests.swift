import Foundation
import Testing

@Suite("ChatBubble rendering")
struct ChatBubbleRenderingTests {
    private var source: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat/Screens/Chat/Views/ChatBubbleView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("assistant messages render all segments instead of a single text blob")
    func assistantMessagesRenderAllSegments() throws {
        let source = try source

        #expect(source.contains("ForEach(Array(message.segments.enumerated())"))
        #expect(source.contains("ChatSegmentCollapsibleCard"))
        #expect(source.contains("ChatBuildProgressView(progress: progress)"))
        #expect(source.contains("ChatMarkdownTextStack"))
        #expect(source.contains("StructuredText(markdown: text)"))
        #expect(!source.contains("rendersMarkdown: !isStreamingAssistant"))
        #expect(source.contains("if isStreamingAssistant"))
        #expect(source.contains("textSelection(.disabled)"))
        #expect(source.contains(".textual.textSelection(.enabled)"))
        #expect(source.contains("allowsTextSelection: !isStreamingAssistant"))
    }

    @Test("rich transcript includes code block and running state affordances")
    func richTranscriptIncludesCodeBlockAndRunningStateAffordances() throws {
        let source = try source

        #expect(source.contains("StructuredText(markdown: text)"))
        #expect(source.contains("ChatCompactDurationFormatter.string"))
        #expect(source.contains("ChatShimmerText(text: segmentTitle)"))
        #expect(source.contains("isActivelyWorking && segment.kind == .thinking"))
        #expect(source.contains("accessibilityReduceMotion"))
    }

    @Test("macOS markdown avoids Textual's text-layout selection feedback loop")
    func macOSMarkdownUsesNativeTextSelection() throws {
        let source = try source
        let stackStart = try #require(source.range(of: "private struct ChatMarkdownTextStack"))
        let cardStart = try #require(source.range(of: "private struct ChatSegmentCollapsibleCard"))
        let stackSource = String(source[stackStart.lowerBound..<cardStart.lowerBound])
        let macOSBranchStart = try #require(stackSource.range(of: "#if os(macOS)"))
        let fallbackBranchStart = try #require(stackSource.range(of: "#else"))
        let macOSBranch = stackSource[macOSBranchStart.lowerBound..<fallbackBranchStart.lowerBound]

        #expect(macOSBranch.contains("structuredText"))
        #expect(!macOSBranch.contains("textual.textSelection"))
        #expect(stackSource.contains(".textual.textSelection(.enabled)"))
        #expect(source.contains(".textSelection(.enabled)"))
    }

    @Test("system activity is grouped without a glass card")
    func systemActivityIsGroupedWithoutGlass() throws {
        let source = try source
        let rowStart = try #require(source.range(of: "private struct ChatSegmentCollapsibleCard"))
        let shimmerStart = try #require(source.range(of: "private struct ChatShimmerText"))
        let rowSource = source[rowStart.lowerBound..<shimmerStart.lowerBound]

        #expect(source.contains("struct ChatSystemMessageGroupView"))
        #expect(source.contains("messages.flatMap"))
        #expect(!rowSource.contains("backportGlassEffect"))
    }

    @Test("system activity starts collapsed and expands from its header")
    func systemActivityStartsCollapsedAndExpandsFromHeader() throws {
        let source = try source
        let groupStart = try #require(source.range(of: "struct ChatSystemMessageGroupView"))
        let itemStart = try #require(source.range(of: "struct ChatSystemSegmentItem"))
        let groupSource = source[groupStart.lowerBound..<itemStart.lowerBound]

        #expect(groupSource.contains("@State private var isExpanded = false"))
        #expect(groupSource.contains("ChatSystemActivityVisibility.visibleItems"))
        #expect(groupSource.contains("isExpanded.toggle()"))
        #expect(groupSource.contains(".buttonStyle(.plain)"))
    }

    @Test("recoverable provider failures link to provider settings")
    func recoverableProviderFailuresLinkToProviderSettings() throws {
        let source = try source

        #expect(source.contains("onOpenProviderSettings"))
        #expect(source.contains("Label(\"Provider Settings\", systemImage: \"gearshape\")"))
    }
}
