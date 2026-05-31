//
//  ACPHTTPTests.swift
//  ACPHTTPTests
//
//  Tests for ACPHTTP module
//

import XCTest
@testable import ACPHTTP
@testable import ACP
@testable import ACPModel

final class ACPHTTPTests: XCTestCase {

    // MARK: - WebSocketTransport Tests

    func testWebSocketTransportCreation() async {
        let url = URL(string: "ws://localhost:8080")!
        let transport = WebSocketTransport(url: url)

        let isConnected = await transport.isConnected
        XCTAssertFalse(isConnected)
    }

    func testWebSocketTransportMessageStream() async {
        let url = URL(string: "ws://localhost:8080")!
        let transport = WebSocketTransport(url: url)

        // Verify the messages stream exists
        _ = transport.messages
        XCTAssert(true, "Messages stream should be available")
    }

    // MARK: - Integration Tests

    func testTransportProtocolConformance() async {
        let url = URL(string: "ws://localhost:8080")!
        let transport = WebSocketTransport(url: url)

        // Verify Transport protocol conformance
        let _: any Transport = transport
        XCTAssert(true, "WebSocketTransport conforms to Transport protocol")
    }
}
