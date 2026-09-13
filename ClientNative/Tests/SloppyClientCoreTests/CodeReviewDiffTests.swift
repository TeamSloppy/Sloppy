import Testing
@testable import SloppyClientCore

@Suite("Code review diff")
struct CodeReviewDiffTests {
    @Test("parses multiple files into aligned old and new rows")
    func parsesSideBySideRows() throws {
        let diff = """
        diff --git a/Sources/Old.swift b/Sources/New.swift
        --- a/Sources/Old.swift
        +++ b/Sources/New.swift
        @@ -10,3 +10,4 @@
         let stable = true
        -let value = oldValue
        +let value = newValue
        +let added = true
         return value
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -Old title
        +New title
        """

        let files = CodeReviewDiffParser.parse(diff)

        #expect(files.count == 2)
        #expect(files[0].displayPath == "Sources/New.swift")
        #expect(files[0].additions == 2)
        #expect(files[0].deletions == 1)
        #expect(files[0].hunks[0].rows[1].old.lineNumber == 11)
        #expect(files[0].hunks[0].rows[1].new.lineNumber == 11)
        #expect(files[0].hunks[0].rows[2].old.kind == .empty)
        #expect(files[0].hunks[0].rows[2].new.kind == .insertion)
        #expect(files[1].displayPath == "README.md")
    }

    @Test("builds a focused agent prompt from unresolved review comments")
    func buildsChatPrompt() {
        let item = CodeReviewItem(
            id: "github:Team/Repo#42",
            providerId: "github",
            providerName: "GitHub",
            repository: "Team/Repo",
            number: 42,
            title: "Improve review UI",
            url: "https://github.com/Team/Repo/pull/42",
            author: "vlad",
            state: .open,
            isDraft: false,
            roles: [.authored],
            reviewDecision: "changes_requested",
            checksStatus: nil,
            labels: [],
            createdAt: nil,
            updatedAt: nil
        )
        let comments = [
            CodeReviewComment(
                id: "open",
                author: "reviewer",
                body: "Please add a test",
                filePath: "Sources/File.swift",
                line: 10,
                originalLine: nil,
                side: "right",
                diffHunk: nil,
                inReplyToId: nil,
                isResolved: false,
                isOutdated: false,
                status: "open",
                createdAt: nil,
                updatedAt: nil
            ),
            CodeReviewComment(
                id: "resolved",
                author: "reviewer",
                body: "Already fixed",
                filePath: nil,
                line: nil,
                originalLine: nil,
                side: nil,
                diffHunk: nil,
                inReplyToId: nil,
                isResolved: true,
                isOutdated: false,
                status: "resolved",
                createdAt: nil,
                updatedAt: nil
            ),
        ]
        let detail = CodeReviewDetail(
            item: item,
            description: nil,
            sourceBranch: "feature/review",
            targetBranch: "main",
            reviewers: ["reviewer"],
            comments: comments,
            commentsError: nil,
            diff: "",
            diffTruncated: false,
            diffError: nil
        )

        let prompt = CodeReviewChatPromptBuilder.prompt(for: detail)

        #expect(prompt.contains("Improve review UI"))
        #expect(prompt.contains("Sources/File.swift:10"))
        #expect(prompt.contains("Please add a test"))
        #expect(!prompt.contains("Already fixed"))
        #expect(prompt.contains("Do not publish or merge unless I ask"))
    }
}
