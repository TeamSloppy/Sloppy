import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Project task inbox")
@MainActor
struct ProjectTaskInboxTests {
    @Test func countsUseCompactMetadataAndPreferLoadedTasks() throws {
        let record = try JSONDecoder().decode(APIProjectRecord.self, from: Data(#"{"id":"p","name":"Project","taskCounts":{"total":10,"ready":0,"inProgress":2,"needsReview":3,"done":3,"blocked":2}}"#.utf8))
        #expect(record.tasks == nil)
        #expect(ProjectTaskInboxStatus.attention.count(in: record) == 2)
        #expect(ProjectTaskInboxStatus.working.count(in: record) == 2)
        #expect(ProjectTaskInboxStatus.review.count(in: record) == 3)
        var loaded = record
        loaded.tasks = [.init(id: "one", title: "Working", status: "in_progress")]
        #expect(ProjectTaskInboxStatus.attention.count(in: loaded) == 0)
        #expect(ProjectTaskInboxStatus.working.count(in: loaded) == 1)
        let cached = try JSONDecoder().decode(APIProjectRecord.self, from: JSONEncoder().encode(record))
        #expect(ProjectTaskInboxStatus.attention.count(in: cached) == 2)
    }

    @Test func loadsCandidatesAndKeepsIdenticalIDsOnDifferentInstancesSeparate() async {
        let fixture = ProjectInboxFixture()
        let first = summary("shared", blocked: 1, instance: "first")
        let second = summary("shared", blocked: 1, instance: "second")
        let empty = summary("empty", blocked: 0)
        let unknown = APIProjectRecord(id: "unknown", name: "Unknown")
        let inbox = ProjectTaskInbox(status: .attention, fetchProject: { try await fixture.fetch($0) })
        await inbox.refresh(projects: [first, second, empty, unknown])
        #expect(Set(await fixture.requests) == [first.storageID, second.storageID, unknown.storageID])
        #expect(inbox.projects.map(\.storageID) == [first.storageID, second.storageID])
        #expect(inbox.projects.allSatisfy { $0.tasks?.first?.status == "blocked" })
        #expect(inbox.errors.isEmpty)
        #expect(inbox.hasLoaded)
        #expect(!inbox.isLoading)
    }

    @Test func failedRefreshKeepsLoadedTasksAndExposesTheError() async {
        let fixture = ProjectInboxFixture()
        let project = summary("shared", blocked: 1)
        let inbox = ProjectTaskInbox(status: .attention, fetchProject: { try await fixture.fetch($0) })
        await inbox.refresh(projects: [project])
        await fixture.failRequests()
        await inbox.refresh(projects: [project])
        #expect(inbox.projects.first?.tasks?.first?.id == "blocked-task")
        #expect(inbox.errors.count == 1)
        #expect(!inbox.isLoading)
    }

    @Test func knownEmptyProjectsNeedNoDetailRequest() async {
        let inbox = ProjectTaskInbox(status: .attention, fetchProject: { _ in
            Issue.record("A known empty project should not load details")
            throw URLError(.badServerResponse)
        })
        await inbox.refresh(projects: [summary("empty", blocked: 0)])
        #expect(inbox.projects.isEmpty)
        #expect(inbox.errors.isEmpty)
        #expect(inbox.hasLoaded)
    }

    @Test func olderSummaryWithoutBlockedCountRemainsUnknown() throws {
        let project = try JSONDecoder().decode(APIProjectRecord.self, from: Data(#"{"id":"p","name":"Project","taskCounts":{"total":1,"ready":0,"inProgress":0,"needsReview":0,"done":0}}"#.utf8))
        #expect(ProjectTaskInboxStatus.attention.count(in: project) == nil)
    }

    private func summary(_ id: String, blocked: Int, instance: String? = nil) -> APIProjectRecord {
        .init(id: id, name: id, taskCounts: .init(total: blocked, ready: 0, inProgress: 0,
            needsReview: 0, done: 0, blocked: blocked), sourceInstanceID: instance)
    }
}

private actor ProjectInboxFixture {
    var requests: [String] = []
    private var shouldFail = false
    func failRequests() { shouldFail = true }
    func fetch(_ summary: APIProjectRecord) throws -> APIProjectRecord {
        requests.append(summary.storageID)
        if shouldFail { throw URLError(.networkConnectionLost) }
        return .init(id: summary.id, name: summary.name, tasks: [
            .init(id: "blocked-task", title: "Task", status: summary.id == "unknown" ? "in_progress" : "blocked")
        ])
    }
}
