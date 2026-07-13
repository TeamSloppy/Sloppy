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
        #expect(source.contains("rendersMarkdown: !isStreamingAssistant"))
        #expect(source.contains("Text(verbatim: text)"))
        #expect(source.contains("if isStreamingAssistant"))
        #expect(source.contains("textSelection(.disabled)"))
    }

    @Test("rich transcript includes code block and running state affordances")
    func richTranscriptIncludesCodeBlockAndRunningStateAffordances() throws {
        let source = try source

        #expect(source.contains("StructuredText(markdown: text)"))
        #expect(source.contains("ChatCompactDurationFormatter.string"))
        #expect(source.contains("ChatShimmerText(text: \"Thinking\")"))
        #expect(source.contains("accessibilityReduceMotion"))
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
}
