import Foundation
import Testing

@testable import Textual

@Suite("Background Markdown parser")
struct BackgroundMarkdownParserTests {
  @Test("parses structured Markdown away from the view update path")
  func parsesMarkdown() async {
    let output = await BackgroundMarkdownParser().parse(
      "# Streaming title\n\nA **formatted** response.",
      baseURL: nil
    )

    let characters = String(output.characters)
    #expect(characters.contains("Streaming title"))
    #expect(characters.contains("A formatted response."))
  }

  @Test("skips work for an already-cancelled streaming request")
  func skipsCancelledRequest() async {
    let parser = BackgroundMarkdownParser()
    let output = await Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return await parser.parse("# Stale response", baseURL: nil)
    }.value

    #expect(output.characters.isEmpty)
  }
}
