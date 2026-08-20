import SloppyClientCore
import Testing

@Suite("Project source-control diff parser")
struct ProjectSourceControlDiffParserTests {
    @Test("collects per-file additions and deletions from unified diff hunks")
    func collectsFileChanges() {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,2 +1,3 @@
        -let old = true
        +let new = true
         let retained = true
        +let added = true
        diff --git a/Tests/AppTests.swift b/Tests/AppTests.swift
        new file mode 100644
        --- /dev/null
        +++ b/Tests/AppTests.swift
        @@ -0,0 +1,2 @@
        +import Testing
        +#expect(true)
        """

        let changes = ProjectSourceControlDiffParser.fileChanges(in: diff)

        #expect(changes == [
            ProjectSourceControlFileChange(path: "Sources/App.swift", linesAdded: 2, linesDeleted: 1),
            ProjectSourceControlFileChange(path: "Tests/AppTests.swift", linesAdded: 2, linesDeleted: 0),
        ])
    }

    @Test("keeps binary changes even when there are no line hunks")
    func keepsBinaryChanges() {
        let diff = """
        diff --git a/Assets/icon.png b/Assets/icon.png
        index 1111111..2222222 100644
        Binary files a/Assets/icon.png and b/Assets/icon.png differ
        """

        #expect(ProjectSourceControlDiffParser.fileChanges(in: diff) == [
            ProjectSourceControlFileChange(path: "Assets/icon.png")
        ])
    }

    @Test("response reports changes from typed source-control data")
    func responseReportsChanges() {
        let response = ProjectWorkingTreeSourceControlResponse(
            providerId: "git",
            isRepository: true,
            linesAdded: 1,
            diff: """
            diff --git a/App.swift b/App.swift
            --- a/App.swift
            +++ b/App.swift
            @@ -0,0 +1 @@
            +let value = 1
            """
        )

        #expect(response.hasChanges)
        #expect(response.fileChanges.first?.path == "App.swift")
    }
}
