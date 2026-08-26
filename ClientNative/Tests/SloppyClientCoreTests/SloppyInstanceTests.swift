import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Sloppy instances")
struct SloppyInstanceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("mesh topology exposes the coordinator directly and peers through relay")
    func topologyBuildsDirectAndRelayInstances() throws {
        let coordinator = try #require(URL(string: "https://work.example.test"))
        let topology = ClientMeshTopology(
            networkId: "personal",
            networkName: "Personal mesh",
            localNode: ClientMeshLocalNode(id: "node_work", name: "Work Mac"),
            nodes: [
                MeshNodeRecord(
                    id: "node_work",
                    name: "Work Mac",
                    publicKey: "work-key",
                    roles: ["core"],
                    status: .online,
                    capabilities: ["sloppy.core.remote"]
                ),
                MeshNodeRecord(
                    id: "node_home",
                    name: "Home Mac",
                    publicKey: "home-key",
                    roles: ["core"],
                    status: .online,
                    capabilities: ["sloppy.core.remote"]
                ),
            ]
        )

        let instances = topology.instances(coordinatorBaseURL: coordinator)
        #expect(instances.map(\.displayName) == ["Work Mac", "Home Mac"])
        #expect(instances[0].endpoint == .direct(baseURL: coordinator))
        #expect(instances[1].endpoint == .relay(
            coordinatorBaseURL: coordinator,
            targetNodeID: "node_home"
        ))
    }

    @Test("instance picker uses English copy on Apple platforms")
    func instancePickerUsesEnglishCopy() throws {
        let macSidebar = try source(
            "Sources/SloppyClient/Navigation/Platforms/macOS/MacMainSidebar.swift"
        )
        let iosSidebar = try source(
            "Sources/SloppyClient/Navigation/Platforms/iOS/IOSMainSidebar.swift"
        )
        let mainViewModel = try source(
            "Sources/SloppyClient/Navigation/Main/MainViewModel.swift"
        )
        let mainView = try source(
            "Sources/SloppyClient/Navigation/Main/MainView.swift"
        )

        #expect(macSidebar.contains("title: \"All\""))
        #expect(macSidebar.contains("Button(\"Manage Instances…\")"))
        #expect(iosSidebar.contains("Label(\"All\""))
        #expect(mainViewModel.contains("return \"All\""))
        #expect(mainView.contains("Text(instance.isLocal ? \"Local\" : \"Via Relay\")"))
        #expect(mainView.contains(".navigationTitle(\"New Chat\")"))
        #expect(mainView.contains("Button(\"Cancel\")"))
    }
}
