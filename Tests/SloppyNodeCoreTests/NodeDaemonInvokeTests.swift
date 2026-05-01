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
