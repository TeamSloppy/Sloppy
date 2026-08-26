import Foundation
import Testing

@Suite("Sites screen layout")
struct SitesScreenLayoutTests {
    @Test("screen fills the detail column from the top leading edge")
    func screenFillsDetailColumn() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyFeatureSites")
            .appendingPathComponent("SitesScreen.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(
            source.contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"
            )
        )
        #expect(source.contains("content\n                .frame(maxWidth: .infinity, maxHeight: .infinity)"))
    }
}
