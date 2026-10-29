import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClient
import SloppyClientCore

private final class AttentionFailureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        let payload = url.path == "/v1/agents"
            ? #"[{"id":"agent","displayName":"Agent","role":"Assistant"}]"#
            : #"{"findings":[],"pendingAnalysisCount":0,"sourceErrors":{"git":"Offline"},"lastAnalysisError":"Analysis unavailable"}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Workspace surfaces")
@MainActor
struct WorkspaceSurfaceTests {
    private func model() throws -> WorkspaceSurfaceModel {
        WorkspaceSurfaceModel(api: SloppyAPIClient(baseURL: try #require(URL(string: "http://127.0.0.1:1"))))
    }

    @Test("Attention uses typed lifecycle fields rather than report wording")
    func attentionLifecycle() throws {
        let model = try model()
        let source = ProactiveSource(id: "task", kind: .task, title: "Review")
        let time = Date(timeIntervalSince1970: 10)
        var finding = ProactiveFinding(agentId: "a", source: source, revision: "1", outcome: .needsInput,
            reason: "Done, everything is finished", evidence: "", nextStep: "Review", sessionId: "chat", createdAt: time)
        #expect(WorkspaceSurfaceModel.active(finding, at: time))
        finding.snoozedUntil = time.addingTimeInterval(60)
        #expect(!WorkspaceSurfaceModel.active(finding, at: time))
        #expect(WorkspaceSurfaceModel.active(finding, at: time.addingTimeInterval(61)))
        finding.snoozedUntil = nil
        finding.dismissedAt = time
        #expect(!WorkspaceSurfaceModel.active(finding, at: time))
        model.findings = [finding]
        #expect(model.unreadCount == 0)
    }

    @Test("Review filters use provider roles")
    func reviewRoles() throws {
        let model = try model()
        model.reviews = [
            CodeReviewItem(id: "review", providerId: "git", providerName: "Git", repository: "sample/repo", title: "Authored words in title", url: "", roles: [.reviewRequested]),
            CodeReviewItem(id: "author", providerId: "git", providerName: "Git", repository: "sample/repo", title: "Review this", url: "", roles: [.authored]),
        ]
        model.reviewFilter = .authored
        #expect(model.visibleReviews.map(\.id) == ["author"])
        model.reviewFilter = .reviewing
        #expect(model.visibleReviews.map(\.id) == ["review"])
        model.query = "missing"
        #expect(model.visibleReviews.isEmpty)
    }

    @Test("Starting creation clears stale values and keeps the chosen delivery context")
    func beginsCreation() throws {
        let model = try model()
        model.creationName = "Previous workspace"
        model.creationCommand = "Old prompt"
        model.errors = ["Old failure"]
        model.beginCreation(.scheduled, agentID: "agent", channelID: "channel")
        #expect(model.creation == .scheduled)
        #expect(model.creationName.isEmpty)
        #expect(model.creationCommand.isEmpty)
        #expect(model.creationAgentID == "agent")
        #expect(model.creationChannelID == "channel")
        #expect(model.errors.isEmpty)
    }

    @Test("Invalid forms stay open without issuing a request")
    func validatesCreation() async throws {
        let model = try model()
        model.beginCreation(.scheduled)
        await model.saveCreation(project: nil)
        #expect(model.creation == .scheduled)
        #expect(model.errors == ["Choose an agent and enter a channel and a prompt."])
        #expect(!model.isSaving)
        model.beginCreation(.canvas)
        await model.saveCreation(project: nil)
        #expect(model.errors == ["Enter a name."])
    }

    @Test("An empty Attention response preserves source and analysis failures")
    func attentionFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttentionFailureProtocol.self]
        let url = try #require(URL(string: "https://attention.invalid"))
        let model = WorkspaceSurfaceModel(api: SloppyAPIClient(baseURL: url, session: URLSession(configuration: config)))
        await model.load(.attention)
        #expect(model.findings.isEmpty)
        #expect(model.errors == ["Agent · git: Offline", "Agent: Analysis unavailable"])
        #expect(!model.isLoading)
    }
}
