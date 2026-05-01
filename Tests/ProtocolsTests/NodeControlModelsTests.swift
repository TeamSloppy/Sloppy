import Foundation
import Testing
@testable import Protocols

@Test("Node action request round-trips computer payloads")
func nodeActionRequestRoundTripsComputerPayloads() throws {
    let request = NodeActionRequest(
        action: .computerClick,
        payload: try JSONValueCoder.encode(ComputerClickPayload(x: 10, y: 20, width: 100, height: 50))
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(NodeActionRequest.self, from: data)
    let payload = try JSONValueCoder.decode(ComputerClickPayload.self, from: decoded.payload)

    #expect(decoded.action == .computerClick)
    #expect(payload.x == 10)
    #expect(payload.y == 20)
    #expect(payload.width == 100)
    #expect(payload.height == 50)
}

@Test("Node action response round-trips screenshot result")
func nodeActionResponseRoundTripsScreenshotResult() throws {
    let result = ComputerScreenshotResult(path: "/tmp/screen.png", width: 800, height: 600, mediaType: "image/png", displayId: "primary")
    let response = NodeActionResponse.success(action: .computerScreenshot, data: try JSONValueCoder.encode(result))

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(NodeActionResponse.self, from: data)
    let decodedData = try #require(decoded.data)
    let decodedResult = try #require(decodedData.asObject)

    #expect(decoded.action == .computerScreenshot)
    #expect(decoded.ok)
    #expect(decodedResult["path"] == .string("/tmp/screen.png"))
    #expect(decodedResult["width"] == .number(800))
    #expect(decodedResult["height"] == .number(600))
    #expect(decodedResult["mediaType"] == .string("image/png"))
}

@Test("Node action error response is stable")
func nodeActionErrorResponseIsStable() throws {
    let response = NodeActionResponse.failure(
        action: .computerKey,
        code: "unsupported_platform",
        message: "Computer control is currently supported on macOS and Windows.",
        retryable: false
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(NodeActionResponse.self, from: data)

    #expect(decoded.action == .computerKey)
    #expect(!decoded.ok)
    #expect(decoded.error?.code == "unsupported_platform")
    #expect(decoded.error?.retryable == false)
}
