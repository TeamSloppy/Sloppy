import XCTest
@testable import ACP

final class ACPClientTests: XCTestCase {

    // MARK: - SessionId Tests

    func testSessionIdEncoding() throws {
        let sessionId = SessionId("test-session-123")
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionId)
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, "\"test-session-123\"")
    }

    func testSessionIdDecoding() throws {
        let json = "\"test-session-456\""
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let sessionId = try decoder.decode(SessionId.self, from: data)
        XCTAssertEqual(sessionId.value, "test-session-456")
    }

    func testSessionIdEquality() {
        let id1 = SessionId("abc")
        let id2 = SessionId("abc")
        let id3 = SessionId("xyz")
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    func testSessionIdHashable() {
        var set = Set<SessionId>()
        set.insert(SessionId("a"))
        set.insert(SessionId("b"))
        set.insert(SessionId("a"))
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - RequestId Tests

    func testRequestIdNumber() throws {
        let requestId = RequestId.number(42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(requestId)
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, "42")
    }

    func testRequestIdString() throws {
        let requestId = RequestId.string("abc-123")
        let encoder = JSONEncoder()
        let data = try encoder.encode(requestId)
        let decoded = String(data: data, encoding: .utf8)
        XCTAssertEqual(decoded, "\"abc-123\"")
    }

    func testRequestIdDecodingNumber() throws {
        let json = "42"
        let data = json.data(using: .utf8)!
        let requestId = try JSONDecoder().decode(RequestId.self, from: data)
        XCTAssertEqual(requestId, .number(42))
    }

    func testRequestIdDecodingString() throws {
        let json = "\"req-999\""
        let data = json.data(using: .utf8)!
        let requestId = try JSONDecoder().decode(RequestId.self, from: data)
        XCTAssertEqual(requestId, .string("req-999"))
    }

    func testRequestIdHashable() {
        var dict: [RequestId: String] = [:]
        dict[.number(1)] = "one"
        dict[.string("two")] = "two"
        dict[.number(1)] = "updated"
        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(dict[.number(1)], "updated")
    }

    // MARK: - TextContent Tests

    func testTextContentEncoding() throws {
        let content = TextContent(text: "Hello, world!")
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "text")
        XCTAssertEqual(json?["text"] as? String, "Hello, world!")
    }

    func testTextContentDecoding() throws {
        let json = """
        {"type": "text", "text": "Hello from JSON"}
        """
        let data = json.data(using: .utf8)!
        let content = try JSONDecoder().decode(TextContent.self, from: data)
        XCTAssertEqual(content.text, "Hello from JSON")
    }

    // MARK: - ContentBlock Tests

    func testContentBlockTextDecoding() throws {
        let json = """
        {"type": "text", "text": "Test message"}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let block = try decoder.decode(ContentBlock.self, from: data)

        if case .text(let text) = block {
            XCTAssertEqual(text.text, "Test message")
        } else {
            XCTFail("Expected text content block")
        }
    }

    func testContentBlockImageDecoding() throws {
        let json = """
        {"type": "image", "data": "iVBORw0KGgo=", "mimeType": "image/png"}
        """
        let data = json.data(using: .utf8)!
        let block = try JSONDecoder().decode(ContentBlock.self, from: data)

        if case .image(let image) = block {
            XCTAssertEqual(image.data, "iVBORw0KGgo=")
            XCTAssertEqual(image.mimeType, "image/png")
        } else {
            XCTFail("Expected image content block")
        }
    }

    func testContentBlockRoundTrip() throws {
        let original = ContentBlock.text(TextContent(text: "Round trip test"))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ContentBlock.self, from: data)

        if case .text(let text) = decoded {
            XCTAssertEqual(text.text, "Round trip test")
        } else {
            XCTFail("Expected text content block")
        }
    }

    // MARK: - JSONRPCRequest Tests

    func testJSONRPCRequestEncoding() throws {
        let request = JSONRPCRequest(
            id: .number(1),
            method: "test/method",
            params: AnyCodable(["key": "value"])
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["id"] as? Int, 1)
        XCTAssertEqual(json?["method"] as? String, "test/method")
    }

    func testJSONRPCRequestDecoding() throws {
        let json = """
        {"jsonrpc": "2.0", "id": 42, "method": "session/new", "params": {"cwd": "/tmp"}}
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)

        XCTAssertEqual(request.id, .number(42))
        XCTAssertEqual(request.method, "session/new")
    }

    func testJSONRPCRequestWithStringId() throws {
        let json = """
        {"jsonrpc": "2.0", "id": "abc-123", "method": "initialize", "params": {}}
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)

        XCTAssertEqual(request.id, .string("abc-123"))
    }

    // MARK: - JSONRPCResponse Tests

    func testJSONRPCResponseSuccess() throws {
        let json = """
        {"jsonrpc": "2.0", "id": 1, "result": {"sessionId": "session-123"}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        XCTAssertEqual(response.id, .number(1))
        XCTAssertNotNil(response.result)
        XCTAssertNil(response.error)
    }

    func testJSONRPCResponseError() throws {
        let json = """
        {"jsonrpc": "2.0", "id": 1, "error": {"code": -32600, "message": "Invalid Request"}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        XCTAssertEqual(response.id, .number(1))
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid Request")
    }

    // MARK: - JSONRPCNotification Tests

    func testJSONRPCNotificationDecoding() throws {
        let json = """
        {"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": "s1"}}
        """
        let data = json.data(using: .utf8)!
        let notification = try JSONDecoder().decode(JSONRPCNotification.self, from: data)

        XCTAssertEqual(notification.method, "session/update")
        XCTAssertNotNil(notification.params)
    }

    func testJSONRPCNotificationWithoutParams() throws {
        let json = """
        {"jsonrpc": "2.0", "method": "heartbeat"}
        """
        let data = json.data(using: .utf8)!
        let notification = try JSONDecoder().decode(JSONRPCNotification.self, from: data)

        XCTAssertEqual(notification.method, "heartbeat")
    }

    // MARK: - ToolKind Tests

    func testToolKindSymbols() {
        XCTAssertEqual(ToolKind.read.symbolName, "doc.text")
        XCTAssertEqual(ToolKind.edit.symbolName, "pencil")
        XCTAssertEqual(ToolKind.execute.symbolName, "terminal")
        XCTAssertEqual(ToolKind.search.symbolName, "magnifyingglass")
        XCTAssertEqual(ToolKind.delete.symbolName, "trash")
        XCTAssertEqual(ToolKind.think.symbolName, "brain")
        XCTAssertEqual(ToolKind.fetch.symbolName, "arrow.down.circle")
        XCTAssertEqual(ToolKind.plan.symbolName, "list.bullet.clipboard")
        XCTAssertEqual(ToolKind.other.symbolName, "wrench.and.screwdriver")
    }

    func testToolKindEncoding() throws {
        let kinds: [ToolKind] = [.read, .edit, .execute, .switchMode, .exitPlanMode]
        let encoder = JSONEncoder()

        for kind in kinds {
            let data = try encoder.encode(kind)
            let decoded = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"", with: "")
            XCTAssertEqual(decoded, kind.rawValue)
        }
    }

    func testToolKindDecoding() throws {
        let testCases: [(String, ToolKind)] = [
            ("\"read\"", .read),
            ("\"edit\"", .edit),
            ("\"execute\"", .execute),
            ("\"switch_mode\"", .switchMode),
            ("\"exit_plan_mode\"", .exitPlanMode),
        ]

        let decoder = JSONDecoder()
        for (json, expected) in testCases {
            let data = json.data(using: .utf8)!
            let result = try decoder.decode(ToolKind.self, from: data)
            XCTAssertEqual(result, expected)
        }
    }

    // MARK: - ToolStatus Tests

    func testToolStatusEncoding() throws {
        let cases: [(ToolStatus, String)] = [
            (.pending, "pending"),
            (.inProgress, "in_progress"),
            (.completed, "completed"),
            (.failed, "failed"),
        ]

        let encoder = JSONEncoder()
        for (status, expected) in cases {
            let data = try encoder.encode(status)
            let decoded = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\"", with: "")
            XCTAssertEqual(decoded, expected)
        }
    }

    // MARK: - StopReason Tests

    func testStopReasonDecoding() throws {
        let testCases: [(String, StopReason)] = [
            ("\"end_turn\"", .endTurn),
            ("\"max_tokens\"", .maxTokens),
            ("\"cancelled\"", .cancelled),
        ]

        let decoder = JSONDecoder()
        for (json, expected) in testCases {
            let data = json.data(using: .utf8)!
            let result = try decoder.decode(StopReason.self, from: data)
            XCTAssertEqual(result, expected)
        }
    }

    func testStopReasonRoundTrip() throws {
        let reasons: [StopReason] = [.endTurn, .maxTokens, .cancelled]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for reason in reasons {
            let data = try encoder.encode(reason)
            let decoded = try decoder.decode(StopReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }

    // MARK: - ClientError Tests

    func testClientErrorDescription() {
        let error1 = ClientError.processNotRunning
        XCTAssertEqual(error1.errorDescription, "Agent process is not running")

        let error2 = ClientError.processFailed(1)
        XCTAssertEqual(error2.errorDescription, "Agent process failed with exit code 1")

        let error3 = ClientError.requestTimeout
        XCTAssertEqual(error3.errorDescription, "Request timed out")

        let error4 = ClientError.invalidResponse
        XCTAssertEqual(error4.errorDescription, "Invalid response from agent")
    }

    // MARK: - ClientCapabilities Tests

    func testClientCapabilitiesEncoding() throws {
        let capabilities = ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["terminal"] as? Bool, true)
        let fs = json?["fs"] as? [String: Any]
        XCTAssertEqual(fs?["readTextFile"] as? Bool, true)
        XCTAssertEqual(fs?["writeTextFile"] as? Bool, true)
    }

    func testClientCapabilitiesMinimal() throws {
        let capabilities = ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
            terminal: false
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["terminal"] as? Bool, false)
    }

    // MARK: - TerminalId Tests

    func testTerminalIdEncoding() throws {
        let terminalId = TerminalId("term-123")
        let data = try JSONEncoder().encode(terminalId)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"term-123\"")
    }

    func testTerminalIdDecoding() throws {
        let json = "\"term-456\""
        let data = json.data(using: .utf8)!
        let terminalId = try JSONDecoder().decode(TerminalId.self, from: data)
        XCTAssertEqual(terminalId.value, "term-456")
    }

    func testTerminalIdHashable() {
        var set = Set<TerminalId>()
        set.insert(TerminalId("a"))
        set.insert(TerminalId("b"))
        set.insert(TerminalId("a"))
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Terminal Request/Response Tests

    func testCreateTerminalRequestEncoding() throws {
        let request = CreateTerminalRequest(
            command: "ls",
            sessionId: "session-1",
            args: ["-la"],
            cwd: "/tmp",
            env: [EnvVariable(name: "FOO", value: "bar")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["command"] as? String, "ls")
        XCTAssertEqual(json?["sessionId"] as? String, "session-1")
        XCTAssertEqual(json?["cwd"] as? String, "/tmp")
        XCTAssertEqual((json?["args"] as? [String])?.first, "-la")
    }

    func testTerminalOutputResponseEncoding() throws {
        let response = TerminalOutputResponse(
            output: "file1.txt\nfile2.txt",
            exitStatus: TerminalExitStatus(exitCode: 0),
            truncated: false
        )

        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["output"] as? String, "file1.txt\nfile2.txt")
        XCTAssertEqual(json?["truncated"] as? Bool, false)
        let exitStatus = json?["exitStatus"] as? [String: Any]
        XCTAssertEqual(exitStatus?["exitCode"] as? Int, 0)
    }

    // MARK: - ToolCall Tests

    func testToolCallEncoding() throws {
        let toolCall = ToolCall(
            toolCallId: "call-123",
            title: "Read File",
            kind: .read,
            status: .completed,
            content: [.content(.text(TextContent(text: "file contents")))],
            locations: [ToolLocation(path: "/tmp/file.txt", line: 1)]
        )

        let data = try JSONEncoder().encode(toolCall)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["toolCallId"] as? String, "call-123")
        XCTAssertEqual(json?["title"] as? String, "Read File")
        XCTAssertEqual(json?["kind"] as? String, "read")
        XCTAssertEqual(json?["status"] as? String, "completed")
    }

    func testToolCallDecoding() throws {
        let json = """
        {
            "toolCallId": "call-456",
            "title": "Execute",
            "kind": "execute",
            "status": "in_progress",
            "content": []
        }
        """
        let data = json.data(using: .utf8)!
        let toolCall = try JSONDecoder().decode(ToolCall.self, from: data)

        XCTAssertEqual(toolCall.toolCallId, "call-456")
        XCTAssertEqual(toolCall.title, "Execute")
        XCTAssertEqual(toolCall.kind, .execute)
        XCTAssertEqual(toolCall.status, .inProgress)
    }

    func testToolCallResolvedKind() {
        let call1 = ToolCall(toolCallId: "1", title: "t", kind: .read, status: .pending, content: [])
        XCTAssertEqual(call1.resolvedKind, .read)

        let call2 = ToolCall(toolCallId: "2", title: "t", kind: nil, status: .pending, content: [])
        XCTAssertEqual(call2.resolvedKind, .other)
    }

    // MARK: - ToolCallContent Tests

    func testToolCallContentDiff() throws {
        let diff = ToolCallDiff(path: "/tmp/file.txt", oldText: "old", newText: "new")
        let content = ToolCallContent.diff(diff)

        XCTAssertEqual(content.displayText, "Modified: /tmp/file.txt")

        if let block = content.asContentBlock, case .text(let text) = block {
            XCTAssertTrue(text.text.contains("/tmp/file.txt"))
            XCTAssertTrue(text.text.contains("new"))
        } else {
            XCTFail("Expected text content block from diff")
        }
    }

    func testToolCallContentTerminal() {
        let terminal = ToolCallTerminal(terminalId: "term-1")
        let content = ToolCallContent.terminal(terminal)

        XCTAssertEqual(content.displayText, "Terminal: term-1")
        XCTAssertNil(content.asContentBlock)
    }

    // MARK: - Plan Tests

    func testPlanEntryEncoding() throws {
        let entry = PlanEntry(
            content: "Implement feature",
            priority: .high,
            status: .inProgress,
            activeForm: "Implementing feature"
        )

        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["content"] as? String, "Implement feature")
        XCTAssertEqual(json?["priority"] as? String, "high")
        XCTAssertEqual(json?["status"] as? String, "in_progress")
        XCTAssertEqual(json?["activeForm"] as? String, "Implementing feature")
    }

    func testPlanEncoding() throws {
        let plan = Plan(entries: [
            PlanEntry(content: "Step 1", priority: .high, status: .completed),
            PlanEntry(content: "Step 2", priority: .medium, status: .pending),
        ])

        let data = try JSONEncoder().encode(plan)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let entries = json?["entries"] as? [[String: Any]]

        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?.first?["content"] as? String, "Step 1")
    }

    // MARK: - SessionUpdate Tests

    func testSessionUpdateAgentMessageChunk() throws {
        let json = """
        {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Hello"}}
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "agent_message_chunk")
        if case .agentMessageChunk(let block) = update, case .text(let text) = block {
            XCTAssertEqual(text.text, "Hello")
        } else {
            XCTFail("Expected agent message chunk with text")
        }
    }

    func testSessionUpdateToolCall() throws {
        let json = """
        {
            "sessionUpdate": "tool_call",
            "toolCallId": "tc-1",
            "status": "completed",
            "content": []
        }
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "tool_call")
        XCTAssertEqual(update.toolCallId, "tc-1")
        XCTAssertEqual(update.status, .completed)
    }

    func testSessionUpdateCurrentModeUpdate() throws {
        let json = """
        {"sessionUpdate": "current_mode_update", "currentModeId": "plan_mode"}
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "current_mode_update")
        XCTAssertEqual(update.currentMode, "plan_mode")
    }

    func testSessionUpdateAvailableCommands() throws {
        let json = """
        {
            "sessionUpdate": "available_commands_update",
            "availableCommands": [
                {"name": "/help", "description": "Show help"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "available_commands_update")
        XCTAssertEqual(update.availableCommands?.count, 1)
        XCTAssertEqual(update.availableCommands?.first?.name, "/help")
    }

    func testSessionUpdateSessionInfoUpdate() throws {
        let json = """
        {
            "sessionUpdate": "session_info_update",
            "title": "Investigate session list support",
            "updatedAt": "2026-03-09T12:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "session_info_update")
        XCTAssertEqual(update.sessionInfo?.title, "Investigate session list support")
        XCTAssertEqual(update.sessionInfo?.updatedAt, "2026-03-09T12:00:00Z")
    }

    func testSessionUpdateSessionInfoUpdatePreservesExplicitNull() throws {
        let json = """
        {
            "sessionUpdate": "session_info_update",
            "title": null
        }
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "session_info_update")
        XCTAssertTrue(update.sessionInfo?.titleUpdate.isClear == true)
        XCTAssertTrue(update.sessionInfo?.updatedAtUpdate.isOmitted == true)
    }

    func testSessionInfoUpdateEncodesExplicitNull() throws {
        let update = SessionInfoUpdate(titleUpdate: .clear)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertTrue(json?.keys.contains("title") == true)
        XCTAssertTrue((json?["title"] is NSNull))
        XCTAssertFalse(json?.keys.contains("updatedAt") == true)
    }

    func testSessionUpdateUsageUpdate() throws {
        let json = """
        {
            "sessionUpdate": "usage_update",
            "used": 4096,
            "size": 200000,
            "cost": {"amount": 0.42, "currency": "USD"}
        }
        """
        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.sessionUpdateType, "usage_update")
        XCTAssertEqual(update.usage?.used, 4096)
        XCTAssertEqual(update.usage?.size, 200000)
        XCTAssertEqual(update.usage?.cost?.currency, "USD")
    }

    // MARK: - SessionConfigOption Tests

    func testSessionConfigOptionDecoding() throws {
        let json = """
        {
            "id": "config-1",
            "name": "Theme",
            "type": "select",
            "currentValue": "dark",
            "options": [
                {"value": "light", "name": "Light"},
                {"value": "dark", "name": "Dark"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(SessionConfigOption.self, from: data)

        XCTAssertEqual(config.id.value, "config-1")
        XCTAssertEqual(config.name, "Theme")
        if case .select(let select) = config.kind {
            XCTAssertEqual(select.currentValue.value, "dark")
        } else {
            XCTFail("Expected select kind")
        }
    }

    func testSessionConfigOptionBooleanDecoding() throws {
        let json = """
        {
            "id": "config-2",
            "name": "Enable Thinking",
            "type": "boolean",
            "currentValue": true,
            "category": "thought_level"
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(SessionConfigOption.self, from: data)

        XCTAssertEqual(config.id.value, "config-2")
        XCTAssertEqual(config.category, "thought_level")
        if case .boolean(let toggle) = config.kind {
            XCTAssertTrue(toggle.currentValue)
        } else {
            XCTFail("Expected boolean kind")
        }
    }

    func testSetSessionConfigOptionRequestBooleanEncoding() throws {
        let request = SetSessionConfigOptionRequest(
            sessionId: SessionId("session-1"),
            configId: SessionConfigId("config-2"),
            value: true
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["sessionId"] as? String, "session-1")
        XCTAssertEqual(json?["configId"] as? String, "config-2")
        XCTAssertEqual(json?["type"] as? String, "boolean")
        XCTAssertEqual(json?["value"] as? Bool, true)
    }

    func testListSessionsResponseDecoding() throws {
        let json = """
        {
            "sessions": [
                {
                    "sessionId": "session-1",
                    "cwd": "/tmp/project",
                    "title": "Fix protocol mismatch",
                    "updatedAt": "2026-03-09T12:00:00Z"
                }
            ],
            "nextCursor": "cursor-2"
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ListSessionsResponse.self, from: data)

        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions.first?.sessionId.value, "session-1")
        XCTAssertEqual(response.sessions.first?.cwd, "/tmp/project")
        XCTAssertEqual(response.nextCursor, "cursor-2")
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableWithPrimitives() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let stringValue = AnyCodable("hello")
        let stringData = try encoder.encode(stringValue)
        let decodedString = try decoder.decode(AnyCodable.self, from: stringData)
        XCTAssertEqual(decodedString.value as? String, "hello")

        let intValue = AnyCodable(42)
        let intData = try encoder.encode(intValue)
        let decodedInt = try decoder.decode(AnyCodable.self, from: intData)
        XCTAssertEqual(decodedInt.value as? Int, 42)

        let boolValue = AnyCodable(true)
        let boolData = try encoder.encode(boolValue)
        let decodedBool = try decoder.decode(AnyCodable.self, from: boolData)
        XCTAssertEqual(decodedBool.value as? Bool, true)
    }

    func testAnyCodableWithDictionary() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let dictValue = AnyCodable(["key": "value", "number": 123] as [String: Any])
        let data = try encoder.encode(dictValue)
        let decoded = try decoder.decode(AnyCodable.self, from: data)

        guard let dict = decoded.value as? [String: Any] else {
            XCTFail("Expected dictionary")
            return
        }
        XCTAssertEqual(dict["key"] as? String, "value")
    }

    func testAnyCodableWithArray() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let arrayValue = AnyCodable([1, 2, 3])
        let data = try encoder.encode(arrayValue)
        let decoded = try decoder.decode(AnyCodable.self, from: data)

        guard let array = decoded.value as? [Int] else {
            XCTFail("Expected array")
            return
        }
        XCTAssertEqual(array, [1, 2, 3])
    }

    // MARK: - Permission Tests

    func testRequestPermissionRequestDecoding() throws {
        let json = """
        {
            "message": "Allow file access?",
            "sessionId": "session-1",
            "options": [
                {"kind": "allow", "name": "Allow", "optionId": "opt-1"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(RequestPermissionRequest.self, from: data)

        XCTAssertEqual(request.message, "Allow file access?")
        XCTAssertEqual(request.sessionId?.value, "session-1")
        XCTAssertEqual(request.options?.count, 1)
        XCTAssertEqual(request.options?.first?.name, "Allow")
    }

    func testPermissionOutcomeEncoding() throws {
        let outcome = PermissionOutcome(optionId: "opt-1")
        let data = try JSONEncoder().encode(outcome)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["outcome"] as? String, "selected")
        XCTAssertEqual(json?["optionId"] as? String, "opt-1")
    }

    // MARK: - ClientInfo Tests

    func testClientInfoEncoding() throws {
        let info = ClientInfo(name: "TestClient", title: "Test Client App", version: "2.0.0")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["name"] as? String, "TestClient")
        XCTAssertEqual(json?["title"] as? String, "Test Client App")
        XCTAssertEqual(json?["version"] as? String, "2.0.0")
    }

    // MARK: - File System Types Tests

    func testReadTextFileRequestEncoding() throws {
        let request = ReadTextFileRequest(path: "/tmp/file.txt", sessionId: "s1", line: 10, limit: 100)
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["path"] as? String, "/tmp/file.txt")
        XCTAssertEqual(json?["sessionId"] as? String, "s1")
        XCTAssertEqual(json?["line"] as? Int, 10)
        XCTAssertEqual(json?["limit"] as? Int, 100)
    }

    func testReadTextFileResponseEncoding() throws {
        let response = ReadTextFileResponse(content: "file contents", totalLines: 50)
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["content"] as? String, "file contents")
        XCTAssertEqual(json?["total_lines"] as? Int, 50)
    }

    func testWriteTextFileResponseEncoding() throws {
        let response = WriteTextFileResponse()
        let data = try JSONEncoder().encode(response)
        // Should encode without errors
        XCTAssertNotNil(data)
    }
}
