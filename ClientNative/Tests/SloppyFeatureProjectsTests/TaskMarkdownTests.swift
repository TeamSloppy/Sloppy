import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureProjects

@Suite("Task markdown")
struct TaskMarkdownTests {
    @Test func trackerMarkupKeepsContentAndMarkdown() {
        let source = "**{red}(Actual result)**\n&nbsp;\n{% cut \"Priorities\" %}\n1. High\n2. Low\n{% endcut %}\n[Link](https://example.com)"
        #expect(TaskMarkdown.normalized(source) == "**Actual result**\n \n### Priorities\n1. High\n2. Low\n\n[Link](https://example.com)")
    }

    @Test func codeIsLiteral() {
        let source = "```text\n&nbsp;\n{% cut \"example\" %}\n```\n`&nbsp;` and **bold** and ``{red}(example) &nbsp;``"
        #expect(TaskMarkdown.normalized(source) == source)
    }

    @Test func trackerLinksBecomeClickableMarkdown() {
        #expect(TaskMarkdown.normalized("Demo ((https://example.com/app demo build))") == "Demo [demo build](https://example.com/app)")
    }

    @Test func ordinaryMarkdownIsUnchanged() {
        let source = "# Heading\n\n> Quote\n\n- **bold**\n- *italic*\n\n| A | B |\n| - | - |\n| 1 | 2 |"
        #expect(TaskMarkdown.normalized(source) == source)
    }
}

@Suite("Task external metadata")
struct TaskExternalMetadataTests {
    @Test func decodesTrackerBadgesAndKeepsLegacyTasksCompatible() throws {
        let data = Data(#"{"id":"TASK-1","title":"Task","status":"needs_review","externalMetadata":{"externalAssignee":"user","providerId":"startrek","externalIssueKey":"MOBILEDEV-1","externalIssueURL":"https://example.com/1","externalStatus":{"display":"In Review","key":"review"},"syncState":"synced"}}"#.utf8)
        let task = try JSONDecoder().decode(APIProjectTask.self, from: data)
        let card = try #require(ProjectKanbanViewModel.buildColumns(from: [task]).flatMap(\.items).first)
        #expect(card.externalMetadata?.externalIssueKey == "MOBILEDEV-1")
        #expect(card.externalMetadata?.externalStatus?.display == "In Review")
        #expect(card.externalMetadata?.syncState == "synced")
        let legacy = try JSONDecoder().decode(APIProjectTaskExternalMetadata.self, from: Data(#"{"externalAssignee":"user"}"#.utf8))
        #expect(legacy.providerId == nil)
        #expect(legacy.externalAssignee == "user")
    }
}
