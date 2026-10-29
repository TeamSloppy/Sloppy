import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Compact project API", .serialized)
struct ProjectListAPITests {
    @Test func listUsesSummaryAndKeepsTaskCountsWithoutLoadingTasks() async throws {
        let client = makeClient()
        let projects = try await client.fetchProjectSummaries()
        let project = try #require(projects.first)
        #expect(project.id == "p")
        #expect(project.tasks == nil)
        #expect(project.inProgressTaskCount == 2)
        #expect(project.toSummary().taskCount == 12)
        #expect(project.toSummary().activeTaskCount == 6)
        let cached = try JSONDecoder().decode(APIProjectRecord.self, from: JSONEncoder().encode(project))
        #expect(cached.taskCounts == project.taskCounts)
        #expect(cached.tasks == nil)
    }

    @Test func overviewKeepsCountsFromCompactRecords() async throws {
        let overview = try await makeClient().fetchOverviewData()
        #expect(overview.activeTasks == 6)
        #expect(overview.completedTasks == 5)
        #expect(overview.projects.first?.taskCount == 12)
    }

    @Test func callersThatNeedTasksFetchEachProjectSeparately() async throws {
        let projects = try await makeClient().fetchProjects()
        #expect(projects.count == 1)
        #expect(projects.first?.tasks?.first?.id == "task")
        // Detail data takes precedence over any counts from an earlier summary.
        #expect(projects.first?.toSummary().taskCount == 1)
    }

    private func makeClient() -> SloppyAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProjectListURLProtocol.self]
        return SloppyAPIClient(baseURL: URL(string: "https://projects.sloppy.test")!,
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
    }
}

private final class ProjectListURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "projects.sloppy.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            let body: String
            switch url.path {
            case "/v1/projects":
                #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "summary", value: "true")])
                body = #"[{"id":"p","name":"Project","taskCounts":{"total":12,"ready":3,"inProgress":2,"needsReview":1,"done":5}}]"#
            case "/v1/projects/p":
                body = #"{"id":"p","name":"Project","tasks":[{"id":"task","title":"Loaded separately","status":"in_progress"}]}"#
            case "/v1/agents":
                body = "[]"
            default:
                Issue.record("Unexpected project request: \(url)")
                body = "[]"
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
