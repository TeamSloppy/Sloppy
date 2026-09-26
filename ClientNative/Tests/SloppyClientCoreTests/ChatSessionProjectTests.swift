import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Chat session project association")
struct ChatSessionProjectTests {
    @Test("local session matches an unscoped project in All instances")
    func localProjectUsesDefaultInstance() {
        let session = ChatSessionSummary(
            id: "chat",
            agentId: "agent",
            title: "Task title",
            projectId: "project",
            sourceInstanceID: "local"
        )
        let project = APIProjectRecord(id: "project", name: "Promozavr")

        #expect(session.project(in: [project], defaultSourceInstanceID: "local")?.name == "Promozavr")
    }

    @Test("same project ID on another instance does not match")
    func projectInstanceMustMatch() {
        let session = ChatSessionSummary(
            id: "chat",
            agentId: "agent",
            title: "Task title",
            projectId: "project",
            sourceInstanceID: "remote"
        )
        let localProject = APIProjectRecord(id: "project", name: "Local", sourceInstanceID: "local")
        let remoteProject = APIProjectRecord(id: "project", name: "Remote", sourceInstanceID: "remote")

        #expect(session.project(in: [localProject, remoteProject], defaultSourceInstanceID: "local")?.name == "Remote")
    }

    @Test("session without a project has no project label")
    func noProject() {
        let session = ChatSessionSummary(id: "chat", agentId: "agent", title: "Task title")

        #expect(session.project(in: [APIProjectRecord(id: "project", name: "Promozavr")]) == nil)
    }
}
