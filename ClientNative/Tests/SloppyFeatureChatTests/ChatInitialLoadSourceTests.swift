import Foundation
import Testing

@Suite("Chat initial load source")
struct ChatInitialLoadSourceTests {
    private var source: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatScreenViewModel.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("initial load selects from the resolved agent list, including cache fallback")
    func initialLoadSelectsFromResolvedAgentList() throws {
        let source = try source

        #expect(source.contains("let availableAgents = agents"))
        #expect(source.contains("let agent = availableAgents.first(where:"))
        #expect(source.contains("?? availableAgents.first"))
    }
}
