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

    @Test("builds focused prompts for a diff line and a reply")
    func buildsFocusedContextPrompts() {
        let reply = reviewComment(
            id: "reply",
            body: "This still races when two requests finish together",
            filePath: "Sources/Worker.swift",
            line: 48,
            inReplyToId: "root",
            diffHunk: "@@ -47,2 +47,2 @@\n-old\n+new"
        )
        let detail = reviewDetail(comments: [reply])

        let replyPrompt = CodeReviewChatPromptBuilder.prompt(for: reply, in: detail)
        let linePrompt = CodeReviewChatPromptBuilder.prompt(
            for: CodeReviewLineContext(
                filePath: "Sources/Worker.swift",
                line: 48,
                side: .new,
                content: "await finish(request)"
            ),
            in: detail
        )

        #expect(replyPrompt.contains("Reply to comment: root"))
        #expect(replyPrompt.contains("Sources/Worker.swift:48"))
        #expect(replyPrompt.contains("This still races"))
        #expect(replyPrompt.contains("```diff"))
        #expect(linePrompt.contains("Selected diff line"))
        #expect(linePrompt.contains("Side: new"))
        #expect(linePrompt.contains("await finish(request)"))
    }

    @Test("open issues prompt excludes resolved and outdated comments")
    func buildsOpenIssuesPrompt() {
        let open = reviewComment(id: "open", body: "Add a regression test")
        var resolved = reviewComment(id: "resolved", body: "Already fixed")
        resolved.isResolved = true
        var outdated = reviewComment(id: "outdated", body: "Old line")
        outdated.isOutdated = true
        let detail = reviewDetail(comments: [open, resolved, outdated])

        let openComments = CodeReviewChatPromptBuilder.openComments(in: detail)
        let prompt = CodeReviewChatPromptBuilder.promptForOpenIssues(in: detail)

        #expect(openComments.map(\.id) == ["open"])
        #expect(prompt.contains("Open review issues (1)"))
        #expect(prompt.contains("Add a regression test"))
        #expect(!prompt.contains("Already fixed"))
        #expect(!prompt.contains("Old line"))
    }

    private func reviewComment(
        id: String,
        body: String,
        filePath: String? = "Sources/File.swift",
        line: Int? = 10,
        inReplyToId: String? = nil,
        diffHunk: String? = nil
    ) -> CodeReviewComment {
        CodeReviewComment(
            id: id,
            author: "reviewer",
            body: body,
            filePath: filePath,
            line: line,
            originalLine: nil,
            side: "right",
            diffHunk: diffHunk,
            inReplyToId: inReplyToId,
            isResolved: false,
            isOutdated: false,
            status: "open",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func reviewDetail(comments: [CodeReviewComment]) -> CodeReviewDetail {
        CodeReviewDetail(
            item: CodeReviewItem(
                id: "arcadia-code-review:42",
                providerId: "arcadia-code-review",
                providerName: "Arcadia",
                repository: "arcadia",
                number: 42,
                title: "Fix review feedback",
                url: "https://a.yandex-team.ru/review/42",
                author: "vlad",
                state: .open,
                isDraft: false,
                roles: [.authored],
                reviewDecision: "changes_requested",
                checksStatus: nil,
                labels: [],
                createdAt: nil,
                updatedAt: nil
            ),
            description: nil,
            sourceBranch: "users/vlad/feature",
            targetBranch: "trunk",
            reviewers: ["reviewer"],
            comments: comments,
            commentsError: nil,
            diff: "",
            diffTruncated: false,
            diffError: nil
        )
    }
}
