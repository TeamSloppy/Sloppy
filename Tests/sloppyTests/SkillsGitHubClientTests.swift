import Foundation
import Testing
@testable import sloppy

@Test
func gitHubContentItemDecodesDirectoryWithNullDownloadURL() throws {
    let payload = """
    {
      "name": "skills",
      "path": "skills",
      "type": "dir",
      "download_url": null
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(SkillsGitHubClient.GitHubContentItem.self, from: payload)

    #expect(item.name == "skills")
    #expect(item.type == "dir")
    #expect(item.downloadUrl == nil)
}

@Test
func gitHubContentItemDecodesFileWithDownloadURL() throws {
    let payload = """
    {
      "name": "README.md",
      "path": "README.md",
      "type": "file",
      "download_url": "https://raw.githubusercontent.com/example/repo/main/README.md"
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder().decode(SkillsGitHubClient.GitHubContentItem.self, from: payload)

    #expect(item.name == "README.md")
    #expect(item.type == "file")
    #expect(item.downloadUrl == "https://raw.githubusercontent.com/example/repo/main/README.md")
}

// MARK: - Frontmatter Parsing

@Test
func parseFrontmatterExtractsAllFields() {
    let content = """
    ---
    name: deploy
    description: Deploy the application to production
    user-invocable: false
    allowed-tools: Bash, Read, Grep
    context: fork
    agent: Explore
    ---

    Deploy the app to production.
    """

    let fm = SkillsGitHubClient.parseFrontmatter(from: content)

    #expect(fm != nil)
    #expect(fm?.name == "deploy")
    #expect(fm?.description == "Deploy the application to production")
    #expect(fm?.userInvocable == false)
    #expect(fm?.allowedTools == ["Bash", "Read", "Grep"])
    #expect(fm?.context == "fork")
    #expect(fm?.agent == "Explore")
}

@Test
func parseFrontmatterReturnsNilForNoFrontmatter() {
    let content = "Just a plain markdown file."

    let fm = SkillsGitHubClient.parseFrontmatter(from: content)

    #expect(fm == nil)
}

@Test
func parseFrontmatterHandlesPartialFields() {
    let content = """
    ---
    name: safe-reader
    allowed-tools: Read, Grep, Glob
    ---

    Read files without changes.
    """

    let fm = SkillsGitHubClient.parseFrontmatter(from: content)

    #expect(fm != nil)
    #expect(fm?.name == "safe-reader")
    #expect(fm?.allowedTools == ["Read", "Grep", "Glob"])
    #expect(fm?.userInvocable == nil)
    #expect(fm?.context == nil)
    #expect(fm?.agent == nil)
}

@Test
func parseFrontmatterHandlesUserInvocableTrue() {
    let content = """
    ---
    name: test-skill
    user-invocable: true
    ---

    Some content.
    """

    let fm = SkillsGitHubClient.parseFrontmatter(from: content)

    #expect(fm?.userInvocable == true)
}
