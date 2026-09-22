import Foundation
import Testing
@testable import SloppyClientCore

@Suite("DeepLink")
struct DeepLinkTests {
    @Test("parses Stream Deck application actions")
    func parsesApplicationActions() {
        #expect(DeepLink.parse(URL(string: "sloppy://open")!) == .open)
        #expect(DeepLink.parse(URL(string: "sloppy://project?id=project%201")!) == .project(id: "project 1"))
        #expect(
            DeepLink.parse(URL(string: "sloppy://task?project=project%201&id=TASK-42")!)
                == .task(projectId: "project 1", taskId: "TASK-42")
        )
        #expect(
            DeepLink.parse(URL(string: "sloppy://session?agent=builder&id=session-1")!)
                == .session(agentId: "builder", sessionId: "session-1")
        )
        #expect(
            DeepLink.parse(URL(string: "sloppy://dictation/toggle?agent=builder&session=session-1")!)
                == .dictationToggle(agentId: "builder", sessionId: "session-1")
        )
    }

    @Test("keeps connect links backwards compatible")
    func parsesConnect() {
        let link = DeepLink.parse(URL(string: "sloppy://connect?host=192.168.1.8&port=25102&label=Desk")!)
        #expect(link == .connect(host: "192.168.1.8", port: 25102, label: "Desk"))
        #expect(link?.serverURL?.absoluteString == "http://192.168.1.8:25102")
        #expect(link?.savedServer?.label == "Desk")
    }

    @Test("rejects incomplete or unsupported actions")
    func rejectsInvalidActions() {
        #expect(DeepLink.parse(URL(string: "sloppy://project")!) == nil)
        #expect(DeepLink.parse(URL(string: "sloppy://task?project=sloppy")!) == nil)
        #expect(DeepLink.parse(URL(string: "sloppy://task?id=SLOPPY-1")!) == nil)
        #expect(DeepLink.parse(URL(string: "sloppy://session?agent=builder")!) == nil)
        #expect(DeepLink.parse(URL(string: "sloppy://dictation/start?agent=builder&session=s")!) == nil)
        #expect(DeepLink.parse(URL(string: "https://example.com")!) == nil)
    }

    @Test("builds percent-encoded application links")
    func buildsApplicationLinks() {
        #expect(
            DeepLink.task(projectId: "project one", taskId: "TASK-42").url?.absoluteString
                == "sloppy://task?project=project%20one&id=TASK-42"
        )
        #expect(
            DeepLink.session(agentId: "build agent", sessionId: "session/1").url?.absoluteString
                == "sloppy://session?agent=build%20agent&id=session/1"
        )
    }
}
