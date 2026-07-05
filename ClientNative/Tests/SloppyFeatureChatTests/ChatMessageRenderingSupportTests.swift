import Foundation
import Testing
@testable import SloppyFeatureChat

@Suite("Chat message rendering support")
struct ChatMessageRenderingSupportTests {
    @Test("compact duration formatter renders seconds and minutes")
    func compactDurationFormatterRendersDurations() {
        #expect(ChatCompactDurationFormatter.string(for: 12) == "12s")
        #expect(ChatCompactDurationFormatter.string(for: 84) == "1m 24s")
        #expect(ChatCompactDurationFormatter.string(for: 7384) == "2h 03m")
    }
}
