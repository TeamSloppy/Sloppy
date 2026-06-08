import Foundation
import Protocols
import SloppyComputerControl
import Testing
@testable import SloppyNodeCore

@Suite("NodeDaemon invoke")
struct NodeDaemonInvokeTests {
    @Test("status returns node metadata")
    func statusReturnsNodeMetadata() async throws {
        let daemon = NodeDaemon(nodeId: "node-test", computerController: FakeComputerController())
        await daemon.connect()

        let response = await daemon.invoke(NodeActionRequest(action: .status))
        let data = try #require(response.data?.asObject)

        #expect(response.ok)
        #expect(data["nodeId"] == .string("node-test"))
        #expect(data["state"] == .string("connected"))
    }

    @Test("click validates negative coordinates before controller call")
    func clickValidatesCoordinates() async throws {
        let daemon = NodeDaemon(nodeId: "node-test", computerController: FakeComputerController())

        let response = await daemon.invoke(NodeActionRequest(
            action: .computerClick,
            payload: try JSONValueCoder.encode(ComputerClickPayload(x: -1, y: 20))
        ))

        #expect(!response.ok)
        #expect(response.error?.code == "invalid_arguments")
    }

    @Test("screenshot returns controller metadata")
    func screenshotReturnsMetadata() async throws {
        let daemon = NodeDaemon(nodeId: "node-test", computerController: FakeComputerController())

        let response = await daemon.invoke(NodeActionRequest(
            action: .computerScreenshot,
            payload: try JSONValueCoder.encode(ComputerScreenshotPayload(outputPath: "/tmp/screen.png"))
        ))
        let data = try #require(response.data?.asObject)

        #expect(response.ok)
        #expect(data["path"] == .string("/tmp/screen.png"))
        #expect(data["width"] == .number(320))
        #expect(data["height"] == .number(200))
        #expect(data["mediaType"] == .string("image/png"))
    }

    @Test("config store initializes and reloads node identity")
    func configStoreInitializesAndReloadsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-tests-")
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("node.json")
        let store = NodeConfigStore(configURL: url)

        let config = try store.initialize(
            name: "Home Mac",
            roles: ["worker", "autopilot"],
            capabilities: ["run_agent", "git"],
            relayURL: "https://sloppy.example.com"
        )
        let reloaded = try store.load()

        #expect(reloaded.identity.nodeId == config.identity.nodeId)
        #expect(reloaded.identity.nodeId.hasPrefix("node_home-mac_"))
        #expect(reloaded.identity.name == "Home Mac")
        #expect(reloaded.identity.publicKey.hasPrefix("ed25519:"))
        #expect(reloaded.identity.privateKey.hasPrefix("ed25519:"))
        #expect(reloaded.identity.roles == ["worker", "autopilot"])
        #expect(reloaded.identity.capabilities == ["run_agent", "git"])
        #expect(reloaded.relayURL == "https://sloppy.example.com")
    }

    @Test("node identity signs and verifies challenge")
    func nodeIdentitySignsAndVerifiesChallenge() throws {
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "signer",
            roles: ["worker"],
            capabilities: ["git"]
        )
        let challenge = Data("challenge".utf8)
        let signature = try NodeIdentityGenerator.sign(challenge: challenge, privateKey: identity.privateKey)

        #expect(signature.hasPrefix("ed25519:"))
        #expect(NodeIdentityGenerator.verify(signature: signature, challenge: challenge, publicKey: identity.publicKey))
        #expect(!NodeIdentityGenerator.verify(signature: signature, challenge: Data("other".utf8), publicKey: identity.publicKey))
    }

    @Test("config store refuses to overwrite existing identity without force")
    func configStoreRefusesOverwriteWithoutForce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-node-tests-")
            .appendingPathComponent(UUID().uuidString)
        let store = NodeConfigStore(configURL: directory.appendingPathComponent("node.json"))

        let first = try store.initialize(name: "first", roles: ["client"], capabilities: [])

        do {
            _ = try store.initialize(name: "second", roles: ["worker"], capabilities: [])
            Issue.record("Expected initialize to throw when config already exists")
        } catch let error as NodeConfigError {
            #expect(error == .alreadyExists(store.configURL.path))
        }

        let reloaded = try store.load()
        #expect(reloaded.identity.nodeId == first.identity.nodeId)
    }
}

private struct FakeComputerController: ComputerControlling {
    func click(_: ComputerClickPayload) async throws -> ComputerControlValue {
        .object(["clicked": .bool(true)])
    }

    func typeText(_ payload: ComputerTypeTextPayload) async throws -> ComputerControlValue {
        .object(["characters": .number(Double(payload.text.count))])
    }

    func key(_ payload: ComputerKeyPayload) async throws -> ComputerControlValue {
        .object(["key": .string(payload.key)])
    }

    func screenshot(_ payload: ComputerScreenshotPayload) async throws -> ComputerScreenshotResult {
        ComputerScreenshotResult(
            path: payload.outputPath ?? "/tmp/screen.png",
            width: 320,
            height: 200,
            mediaType: "image/png",
            displayId: "fake"
        )
    }
}
