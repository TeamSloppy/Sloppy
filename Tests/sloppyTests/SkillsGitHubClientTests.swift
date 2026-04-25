import Foundation
import Testing
@testable import sloppy

private final class SkillsGitHubClientMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private func makeSkillsGitHubClient() -> SkillsGitHubClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SkillsGitHubClientMockURLProtocol.self]
    return SkillsGitHubClient(urlSession: URLSession(configuration: config))
}

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

@Test
func downloadSkillUsesExpectedContentsRefBehavior() async throws {
    let requests = TestLocked<[URLRequest]>([])
    SkillsGitHubClientMockURLProtocol.requestHandler = { request in
        requests.withLock { $0.append(request) }

        guard let url = request.url else {
            throw URLError(.badURL)
        }

        switch url.absoluteString {
        case "https://api.github.com/repos/18studio/avito-skill/contents":
            let payload = """
            [
              {
                "name": "SKILL.md",
                "path": "SKILL.md",
                "type": "file",
                "download_url": "https://raw.githubusercontent.com/18studio/avito-skill/master/SKILL.md"
              }
            ]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        case "https://raw.githubusercontent.com/18studio/avito-skill/master/SKILL.md":
            let payload = """
            ---
            name: avito-skill
            description: Install me from the default branch
            ---

            Skill body.
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        default:
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
    defer { SkillsGitHubClientMockURLProtocol.requestHandler = nil }

    let client = makeSkillsGitHubClient()
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    let downloaded = try await client.downloadSkill(
        owner: "18studio",
        repo: "avito-skill",
        destination: destination
    )

    let firstCaptured = requests.withLock { $0 }
    #expect(firstCaptured.count == 2)
    #expect(firstCaptured[0].url?.absoluteString == "https://api.github.com/repos/18studio/avito-skill/contents")
    #expect(firstCaptured[0].url?.query == nil)
    #expect(downloaded.name == "avito-skill")
    #expect(downloaded.version == "default")

    requests.withLock { $0.removeAll() }
    SkillsGitHubClientMockURLProtocol.requestHandler = { request in
        requests.withLock { $0.append(request) }

        guard let url = request.url else {
            throw URLError(.badURL)
        }

        switch url.absoluteString {
        case "https://api.github.com/repos/18studio/avito-skill/contents?ref=master":
            let payload = """
            [
              {
                "name": "SKILL.md",
                "path": "SKILL.md",
                "type": "file",
                "download_url": "https://raw.githubusercontent.com/18studio/avito-skill/master/SKILL.md"
              }
            ]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        case "https://raw.githubusercontent.com/18studio/avito-skill/master/SKILL.md":
            let payload = "Skill body.".data(using: .utf8)!
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        default:
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
    defer { SkillsGitHubClientMockURLProtocol.requestHandler = nil }

    let explicitDestination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    let explicitDownload = try await client.downloadSkill(
        owner: "18studio",
        repo: "avito-skill",
        version: "master",
        destination: explicitDestination
    )

    let secondCaptured = requests.withLock { $0 }
    #expect(secondCaptured.count == 2)
    #expect(secondCaptured[0].url?.absoluteString == "https://api.github.com/repos/18studio/avito-skill/contents?ref=master")
    #expect(explicitDownload.version == "master")
}
