import Foundation
import Testing
import SloppyClientCore
@testable import SloppyFeatureProjects

@Suite("Task activity", .serialized)
struct TaskActivityTests {
    @Test func separatesTypedAndLegacyCommentsWithoutGuessingText() {
        let date = Date(timeIntervalSince1970: 100)
        let comments = [
            TaskComment(id: "legacy", taskId: "t", content: "service", authorActorId: "system", createdAt: date),
            TaskComment(id: "result", taskId: "t", content: "Done", authorActorId: "system", createdAt: date, kind: "result"),
            TaskComment(id: "technical", taskId: "t", content: "status", authorActorId: "agent", createdAt: date, kind: "technical"),
            TaskComment(id: "user", taskId: "t", content: "retry heartbeat", authorActorId: "user", createdAt: date),
            TaskComment(id: "imported", taskId: "t", content: "PR opened", authorActorId: "user", sourceAuthor: "robot", createdAt: date)
        ]
        let technical = TaskActivityViewModel.filterComments(comments, technical: true, query: "", newestFirst: true)
        #expect(Set(technical.map(\.id)) == ["legacy", "technical"])
        let normal = TaskActivityViewModel.filterComments(comments, technical: false, query: "", newestFirst: true)
        #expect(Set(normal.map(\.id)) == ["result", "user", "imported"])
        #expect(TaskActivityViewModel.filterComments(comments, technical: false, query: "ROBOT", newestFirst: true).map(\.id) == ["imported"])
    }

    @Test func trackerRobotFormattingIsReadableAndCodeStaysLiteral() {
        let text = ###"Pull request ##""MOBILEDEV-88796: title""## to ##""trunk""## !!(blue)OPENED!! by staff:user"###
        #expect(TaskMarkdown.normalized(text) == "Pull request `MOBILEDEV-88796: title` to `trunk` **OPENED** by staff:user")
        let code = "```\n\(text)\n```"
        #expect(TaskMarkdown.normalized(code) == code)
    }

    @Test @MainActor func loadsTabsOnDemandAndCommentsShareCache() async throws {
        let session = Self.session()
        defer { session.invalidateAndCancel() }
        ActivityRequestRecorder.shared.reset()
        let model = TaskActivityViewModel(api: SloppyAPIClient(baseURL: URL(string: "https://activity.test")!, session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)))
        await model.load(.comments, projectId: "p", taskId: "t")
        #expect(model.errorMessage == nil)
        #expect(model.comments.count == 2)
        await model.load(.technical, projectId: "p", taskId: "t")
        #expect(ActivityRequestRecorder.shared.paths.count == 1)
        await model.load(.history, projectId: "p", taskId: "t")
        #expect(model.activities.first?.oldValue == "ready")
        await model.load(.logs, projectId: "p", taskId: "t")
        #expect(model.logs.first?.ok == false)
        await model.load(.clarifications, projectId: "p", taskId: "t")
        #expect(model.clarifications.first?.questionText == "Which target?")
        await model.load(.review, projectId: "p", taskId: "t")
        #expect(model.diff?.branchName == "feature")
        #expect(model.reviewComments.first?.lineNumber == 7)
        #expect(model.diffLines.contains("+new"))
        #expect(!model.isLoading)
    }

    @Test @MainActor func failedTabDoesNotEraseOtherDataAndCanRetry() async throws {
        let session = Self.session()
        defer { session.invalidateAndCancel() }
        let model = TaskActivityViewModel(api: SloppyAPIClient(baseURL: URL(string: "https://activity.test")!, session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)))
        await model.load(.comments, projectId: "p", taskId: "failure")
        await model.load(.history, projectId: "p", taskId: "failure")
        #expect(model.errorMessage != nil)
        #expect(model.comments.count == 2)
        #expect(!model.hasLoaded(.history))
        await model.load(.comments, projectId: "p", taskId: "failure")
        #expect(model.errorMessage == nil)
        #expect(model.comments.count == 2)
    }

    @Test @MainActor func writesUseTaskEndpointsAndUpdateLocalState() async throws {
        let session = Self.session()
        defer { session.invalidateAndCancel() }
        let model = TaskActivityViewModel(api: SloppyAPIClient(baseURL: URL(string: "https://activity.test")!, session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)))
        await model.load(.comments, projectId: "p", taskId: "t")
        #expect(await model.addComment("New comment", projectId: "p", taskId: "t"))
        #expect(model.comments.first?.id == "added")
        #expect(model.comments.first?.effectiveKind == "user_comment")
        await model.load(.clarifications, projectId: "p", taskId: "t")
        let question = try #require(model.clarifications.first)
        await model.answer(question, selected: ["mac"], note: "Use macOS", projectId: "p", taskId: "t")
        #expect(model.clarifications.first?.status == "answered")
        await model.load(.review, projectId: "p", taskId: "t")
        let comment = try #require(model.reviewComments.first)
        await model.resolveReviewComment(comment, projectId: "p", taskId: "t")
        #expect(model.reviewComments.first?.resolved == true)
        #expect(await model.decideReview(approve: false, reason: "Fix tests", projectId: "p", taskId: "t"))
        #expect(model.actionError == nil)
    }

    @Test @MainActor func primaryTaskLoadsWithoutFetchingAllActivityTabs() async throws {
        let session = Self.session()
        defer { session.invalidateAndCancel() }
        ActivityRequestRecorder.shared.reset()
        let model = TaskDetailViewModel(apiClient: SloppyAPIClient(baseURL: URL(string: "https://activity.test")!, session: session,
            authSessionStore: AuthSessionStore(persistence: .memory)))
        await model.load(projectId: "p", taskId: "t")
        #expect(model.task?.id == "t")
        #expect(model.errorMessage == nil)
        #expect(ActivityRequestRecorder.shared.paths == ["/v1/projects/p"])
        #expect(model.activity.comments.isEmpty)
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivityFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ActivityRequestRecorder: @unchecked Sendable {
    static let shared = ActivityRequestRecorder()
    private let lock = NSLock()
    private var values: [String] = []
    var paths: [String] { lock.withLock { values } }
    func record(_ path: String) { lock.withLock { values.append(path) } }
    func reset() { lock.withLock { values = [] } }
}

private final class ActivityFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        ActivityRequestRecorder.shared.record(path)
        var data: String
        switch request.url!.lastPathComponent {
        case "p":
            data = String(decoding: try! JSONEncoder().encode(APIProjectRecord(id: "p", name: "Project", tasks: [APIProjectTask(id: "t", title: "Task", status: "backlog")])), as: UTF8.self)
        case "comments": data = #"[{"id":"c","taskId":"t","content":"Comment","authorActorId":"user","isAgentReply":false,"createdAt":"2026-09-13T12:00:00Z"},{"id":"tech","taskId":"t","content":"Trace","authorActorId":"system","isAgentReply":false,"kind":"technical","createdAt":"2026-09-13T12:00:01Z"}]"#
        case "activities": data = #"[{"id":"a","taskId":"t","field":"status","oldValue":"ready","newValue":"in_progress","actorId":"agent","createdAt":"2026-09-13T12:00:00Z"}]"#
        case "logs": data = #"[{"id":"l","taskId":"t","kind":"tool_invocation","title":"Test","ok":false,"durationMs":15,"createdAt":"2026-09-13T12:00:00Z"}]"#
        case "clarifications": data = #"[{"id":"q","status":"pending","targetType":"user","questionText":"Which target?","options":[{"id":"mac","label":"macOS"}],"allowNote":true,"selectedOptionIds":[],"createdAt":"2026-09-13T12:00:00Z"}]"#
        case "diff": data = #"{"diff":"-old\n+new","branchName":"feature","baseBranch":"main","hasChanges":true}"#
        case "review-comments": data = #"[{"id":"r","filePath":"app.swift","lineNumber":7,"content":"Check","author":"reviewer","resolved":false,"createdAt":"2026-09-13T12:00:00Z"}]"#
        default: data = "[]"
        }
        if request.httpMethod == "POST" || request.httpMethod == "PATCH" {
            let stream = request.httpBodyStream
            var body = request.httpBody ?? Data()
            if let stream {
                stream.open()
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
                stream.close()
            }
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            switch request.url!.lastPathComponent {
            case "comments":
                #expect(payload["content"] as? String == "New comment")
                #expect(payload["kind"] as? String == "user_comment")
                data = #"{"id":"added","taskId":"t","content":"New comment","authorActorId":"user","isAgentReply":false,"kind":"user_comment","createdAt":"2026-09-13T12:00:02Z"}"#
            case "answer":
                #expect(payload["selectedOptionIds"] as? [String] == ["mac"])
                #expect(payload["note"] as? String == "Use macOS")
                data = #"{"id":"q","status":"answered","targetType":"user","questionText":"Which target?","options":[],"allowNote":true,"selectedOptionIds":["mac"],"note":"Use macOS","createdAt":"2026-09-13T12:00:00Z"}"#
            case "r":
                #expect(payload["resolved"] as? Bool == true)
                data = #"{"id":"r","filePath":"app.swift","lineNumber":7,"content":"Check","author":"reviewer","resolved":true,"createdAt":"2026-09-13T12:00:00Z"}"#
            case "reject":
                #expect(payload["reason"] as? String == "Fix tests")
                data = #"{"ok":"true"}"#
            default: Issue.record("Unexpected mutation path: \(path)")
            }
        }
        let status = path.contains("failure/activities") ? 500 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(data.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
