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
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatBubbleView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("assistant messages render all segments instead of a single text blob")
    func assistantMessagesRenderAllSegments() throws {
        let source = try source

        #expect(source.contains("ForEach(Array(message.segments.enumerated())"))
        #expect(source.contains("ChatSegmentCollapsibleCard"))
        #expect(source.contains("ChatMarkdownTextStack"))
    }

    @Test("rich transcript includes code block and running state affordances")
    func richTranscriptIncludesCodeBlockAndRunningStateAffordances() throws {
        let source = try source

        #expect(source.contains("ChatCodeBlockView"))
        #expect(source.contains("ChatCompactDurationFormatter.string"))
        #expect(source.contains("ChatShimmerView"))
    }
}
