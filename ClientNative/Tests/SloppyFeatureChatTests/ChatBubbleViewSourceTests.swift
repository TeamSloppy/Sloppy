import Foundation
import Testing

@Suite("ChatBubbleView source")
struct ChatBubbleViewSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("collapsible cards only use live timeline updates while a segment is still running")
    func collapsibleCardsOnlyUseTimelineViewForRunningSegments() throws {
        let source = try source("Sources", "SloppyFeatureChat", "Screens", "Chat", "Views", "ChatBubbleView.swift")

        #expect(source.contains("if showsLiveDuration"))
        #expect(source.contains("TimelineView(.periodic(from: .now, by: 1))"))
        #expect(source.contains("timelineRow(durationText: durationLabel(at: timeline.date))"))
        #expect(source.contains("timelineRow(durationText: staticDurationLabel)"))
        #expect(source.contains("private var showsLiveDuration: Bool"))
        #expect(source.contains("segment.finishedAt == nil"))
    }
}
