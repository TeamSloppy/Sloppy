//
//  ACPModelTests.swift
//  ACPModelTests
//
//  Tests for ACPModel types
//

import XCTest
@testable import ACPModel

final class ACPModelTests: XCTestCase {

    // MARK: - Message Tests

    func testJSONRPCRequestEncoding() throws {
        let request = JSONRPCRequest(
            id: .number(1),
            method: "test/method",
            params: AnyCodable(["key": "value"])
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? Int, 1)
        XCTAssertEqual(json["method"] as? String, "test/method")
    }

    func testJSONRPCResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {"status": "ok"}
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(JSONRPCResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.id, .number(1))
        XCTAssertNotNil(response.result)
        XCTAssertNil(response.error)
    }

    func testMessageDecoding() throws {
        let requestJson = """
        {"jsonrpc": "2.0", "id": 1, "method": "test", "params": {}}
        """
        let notificationJson = """
        {"jsonrpc": "2.0", "method": "notify", "params": {}}
        """
        let responseJson = """
        {"jsonrpc": "2.0", "id": 1, "result": null}
        """

        let decoder = JSONDecoder()

        let request = try decoder.decode(Message.self, from: requestJson.data(using: .utf8)!)
        if case .request(let r) = request {
            XCTAssertEqual(r.method, "test")
        } else {
            XCTFail("Expected request")
        }

        let notification = try decoder.decode(Message.self, from: notificationJson.data(using: .utf8)!)
        if case .notification(let n) = notification {
            XCTAssertEqual(n.method, "notify")
        } else {
            XCTFail("Expected notification")
        }

        let response = try decoder.decode(Message.self, from: responseJson.data(using: .utf8)!)
        if case .response(let r) = response {
            XCTAssertEqual(r.id, .number(1))
        } else {
            XCTFail("Expected response")
        }
    }

    func testMessageWithNullIdDecodesAsNotification() throws {
        let notificationWithNullId = """
        {"jsonrpc":"2.0","id":null,"method":"session/update","params":{"sessionId":"s1"}}
        """

        let message = try JSONDecoder().decode(Message.self, from: notificationWithNullId.data(using: .utf8)!)
        if case .notification(let notification) = message {
            XCTAssertEqual(notification.method, "session/update")
        } else {
            XCTFail("Expected notification for null id")
        }
    }

    func testMessageWithInvalidIdTypeDecodesAsNotification() throws {
        let notificationWithInvalidId = """
        {"jsonrpc":"2.0","id":{"bad":true},"method":"session/update","params":{"sessionId":"s1"}}
        """

        let message = try JSONDecoder().decode(Message.self, from: notificationWithInvalidId.data(using: .utf8)!)
        if case .notification(let notification) = message {
            XCTAssertEqual(notification.method, "session/update")
        } else {
            XCTFail("Expected notification for invalid id type")
        }
    }

    // MARK: - Session Tests

    func testSessionIdEncoding() throws {
        let sessionId = SessionId("test-session-123")
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionId)
        let string = String(data: data, encoding: .utf8)

        XCTAssertEqual(string, "\"test-session-123\"")
    }

    func testClientInfoEncoding() throws {
        let info = ClientInfo(name: "TestClient", title: "Test", version: "1.0.0")
        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "TestClient")
        XCTAssertEqual(json["title"] as? String, "Test")
        XCTAssertEqual(json["version"] as? String, "1.0.0")
    }

    // MARK: - Content Tests

    func testTextContentEncoding() throws {
        let content = TextContent(text: "Hello, world!")
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "text")
        XCTAssertEqual(json["text"] as? String, "Hello, world!")
    }

    func testContentBlockDecoding() throws {
        let textJson = """
        {"type": "text", "text": "Hello"}
        """

        let decoder = JSONDecoder()
        let block = try decoder.decode(ContentBlock.self, from: textJson.data(using: .utf8)!)

        if case .text(let content) = block {
            XCTAssertEqual(content.text, "Hello")
        } else {
            XCTFail("Expected text content")
        }
    }

    // MARK: - Tool Tests

    func testToolKindRawValues() {
        XCTAssertEqual(ToolKind.read.rawValue, "read")
        XCTAssertEqual(ToolKind.edit.rawValue, "edit")
        XCTAssertEqual(ToolKind.execute.rawValue, "execute")
        XCTAssertEqual(ToolKind.switchMode.rawValue, "switch_mode")
    }

    func testToolStatusRawValues() {
        XCTAssertEqual(ToolStatus.pending.rawValue, "pending")
        XCTAssertEqual(ToolStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(ToolStatus.completed.rawValue, "completed")
        XCTAssertEqual(ToolStatus.failed.rawValue, "failed")
    }

    // MARK: - Capabilities Tests

    func testClientCapabilitiesEncoding() throws {
        let capabilities = ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true,
            meta: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["terminal"] as? Bool, true)
        let fs = json["fs"] as! [String: Any]
        XCTAssertEqual(fs["readTextFile"] as? Bool, true)
        XCTAssertEqual(fs["writeTextFile"] as? Bool, true)
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableWithPrimitives() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let intValue = AnyCodable(42)
        let intData = try encoder.encode(intValue)
        XCTAssertEqual(String(data: intData, encoding: .utf8), "42")

        let stringValue = AnyCodable("hello")
        let stringData = try encoder.encode(stringValue)
        XCTAssertEqual(String(data: stringData, encoding: .utf8), "\"hello\"")

        let boolValue = AnyCodable(true)
        let boolData = try encoder.encode(boolValue)
        XCTAssertEqual(String(data: boolData, encoding: .utf8), "true")
    }

    func testAnyCodableWithDict() throws {
        let encoder = JSONEncoder()
        let value = AnyCodable(["key": "value", "number": 123] as [String: Any])
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["key"] as? String, "value")
        XCTAssertEqual(json["number"] as? Int, 123)
    }

    // MARK: - Request/Response Tests

    func testInitializeRequestEncoding() throws {
        let request = InitializeRequest(
            protocolVersion: 1,
            clientCapabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: true
            ),
            clientInfo: ClientInfo(name: "Test", title: nil, version: "1.0")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["protocolVersion"] as? Int, 1)
        XCTAssertNotNil(json["clientCapabilities"])
        XCTAssertNotNil(json["clientInfo"])
    }

    func testSessionPromptRequestEncoding() throws {
        let request = SessionPromptRequest(
            sessionId: SessionId("session-1"),
            prompt: [.text(TextContent(text: "Hello"))]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["sessionId"] as? String, "session-1")
        XCTAssertNotNil(json["prompt"])
    }
}
