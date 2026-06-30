import Foundation
import Testing
@testable import SloppyFeatureChat

@Suite("Chat message rendering support")
struct ChatMessageRenderingSupportTests {
    @Test("markdown parser splits headings paragraphs and fenced code blocks")
    func markdownParserSplitsContentBlocks() {
        let source = """
        # Title

        Intro paragraph with [link](https://example.com).

        ```swift
        let x = 1
        print(x)
        ```

        ## Details
        Final line
        """

        let blocks = ChatMarkdownBlockParser.parse(source)

        #expect(blocks.count == 5)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Intro paragraph with [link](https://example.com)."))
        #expect(blocks[2] == .code(language: "swift", code: "let x = 1\nprint(x)"))
        #expect(blocks[3] == .heading(level: 2, text: "Details"))
        #expect(blocks[4] == .paragraph("Final line"))
    }

    @Test("markdown parser supports deeper headings and tilde code fences")
    func markdownParserSupportsMoreHeadingsAndCodeFences() {
        let source = """
        #### Deep Title

        ~~~json
        {"ok":true}
        ~~~

        ###### Final Heading
        """

        let blocks = ChatMarkdownBlockParser.parse(source)

        #expect(blocks.count == 3)
        #expect(blocks[0] == .heading(level: 4, text: "Deep Title"))
        #expect(blocks[1] == .code(language: "json", code: #"{"ok":true}"#))
        #expect(blocks[2] == .heading(level: 6, text: "Final Heading"))
    }

    @Test("compact duration formatter renders seconds and minutes")
    func compactDurationFormatterRendersDurations() {
        #expect(ChatCompactDurationFormatter.string(for: 12) == "12s")
        #expect(ChatCompactDurationFormatter.string(for: 84) == "1m 24s")
        #expect(ChatCompactDurationFormatter.string(for: 7384) == "2h 03m")
    }
}
