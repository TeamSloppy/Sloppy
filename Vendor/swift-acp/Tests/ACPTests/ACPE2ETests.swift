import XCTest
@testable import ACP

/// E2E tests using a mock agent script that responds to JSON-RPC messages
final class ACPE2ETests: XCTestCase {

    var mockAgentPath: String!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mockAgentPath = tempDir.appendingPathComponent("mock-agent.sh").path
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockAgent(script: String) throws {
        let fullScript = """
        #!/bin/bash
        \(script)
        """
        try fullScript.write(toFile: mockAgentPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockAgentPath)
    }

    private func makeCapabilities() -> ClientCapabilities {
        ClientCapabilities(
            fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
            terminal: true
        )
    }

    // MARK: - E2E Tests

    func testClientLaunchAndTerminate() async throws {
        try createMockAgent(script: """
        # Simple agent that exits on signal
        trap 'exit 0' TERM
        sleep 10
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        // Should be able to terminate cleanly
        await client.terminate()
    }

    func testInitializeRequest() async throws {
        try createMockAgent(script: """
        # Read request and send response
        read -r line
        # Extract id from request
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"MockAgent","version":"1.0.0"}}}'
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let response = try await client.initialize(
            protocolVersion: 1,
            capabilities: makeCapabilities(),
            timeout: 5.0
        )

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "MockAgent")
        XCTAssertEqual(response.agentInfo?.version, "1.0.0")

        await client.terminate()
    }

    func testNewSessionRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"MockAgent","version":"1.0.0"}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let session = try await client.newSession(
            workingDirectory: "/tmp",
            timeout: 5.0
        )

        XCTAssertEqual(session.sessionId.value, "session-123")

        await client.terminate()
    }

    func testListSessionsRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"list":{}}}}}'
            elif [ "$method" = "session/list" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessions":[{"sessionId":"session-123","cwd":"/tmp/project","title":"Investigate latest ACP changes","updatedAt":"2026-03-09T12:00:00Z"}],"nextCursor":"cursor-2"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let response = try await client.listSessions(cwd: "/tmp/project", timeout: 5.0)

        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions.first?.sessionId.value, "session-123")
        XCTAssertEqual(response.sessions.first?.title, "Investigate latest ACP changes")
        XCTAssertEqual(response.nextCursor, "cursor-2")

        await client.terminate()
    }

    func testNotificationStream() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
                # Send a notification after response
                echo '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello from agent"}}}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let notificationStream = await client.notifications

        // Start listening for notifications before sending request
        let notificationTask = Task {
            var receivedNotification = false
            for await notification in notificationStream {
                if notification.method == "session/update" {
                    receivedNotification = true
                    break
                }
            }
            return receivedNotification
        }

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        // Give time for notification to arrive
        try await Task.sleep(nanoseconds: 500_000_000)

        await client.terminate()

        let result = await notificationTask.value
        XCTAssertTrue(result, "Should have received session/update notification")
    }

    func testRequestTimeout() async throws {
        try createMockAgent(script: """
        # Never respond - keep process alive so timeout is the dominant failure mode.
        read -r line
        sleep 5
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 0.5)
            XCTFail("Should have thrown timeout error")
        } catch let error as ClientError {
            switch error {
            case .requestTimeout:
                break // Expected
            default:
                XCTFail("Expected requestTimeout, got: \(error)")
            }
        }

        await client.terminate()
    }

    func testInitializeWithNonJSONPrefixSameLine() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                # Non-JSON prefix on the same stdout line before a valid JSON message.
                printf 'NONJSON_PREFIX'
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"MockAgent","version":"1.0.0"}}}'
                break
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let response = try await client.initialize(
            protocolVersion: 1,
            capabilities: makeCapabilities(),
            timeout: 5.0
        )

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "MockAgent")

        await client.terminate()
    }

    func testInitializeRecoversAfterMalformedJSONLine() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                # Malformed JSON line that should be discarded.
                echo '{"jsonrpc":"2.0","id":'$id',"result":'
                # Valid response must still be parsed.
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{},"agentInfo":{"name":"RecoveredAgent","version":"1.0.0"}}}'
                break
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        let response = try await client.initialize(
            protocolVersion: 1,
            capabilities: makeCapabilities(),
            timeout: 5.0
        )

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "RecoveredAgent")

        await client.terminate()
    }

    func testProcessTerminationError() async throws {
        try createMockAgent(script: """
        # Exit immediately
        exit 1
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        // Wait for process to exit
        try await Task.sleep(nanoseconds: 200_000_000)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 2.0)
            XCTFail("Should have thrown error")
        } catch let error as ClientError {
            switch error {
            case .processNotRunning, .processFailed:
                break // Expected
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }

        await client.terminate()
    }

    func testDebugStream() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            break
        done
        """)

        let client = Client()
        await client.enableDebugStream()

        try await client.launch(agentPath: mockAgentPath)

        var debugMessages: [DebugMessage] = []
        let debugTask = Task {
            guard let stream = await client.debugMessages else { return }
            for await message in stream {
                debugMessages.append(message)
                if debugMessages.count >= 2 { break }
            }
        }

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        // Give time for debug messages to be collected
        try await Task.sleep(nanoseconds: 500_000_000)

        await client.terminate()
        debugTask.cancel()

        XCTAssertGreaterThanOrEqual(debugMessages.count, 1)

        // Should have at least one outgoing message (the request)
        let outgoing = debugMessages.filter { $0.direction == .outgoing }
        XCTAssertGreaterThanOrEqual(outgoing.count, 1)
    }

    func testMultipleSequentialRequests() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-'$id'"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        // Create multiple sessions sequentially
        let session1 = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)
        let session2 = try await client.newSession(workingDirectory: "/var", timeout: 5.0)
        let session3 = try await client.newSession(workingDirectory: "/home", timeout: 5.0)

        XCTAssertNotEqual(session1.sessionId.value, session2.sessionId.value)
        XCTAssertNotEqual(session2.sessionId.value, session3.sessionId.value)

        await client.terminate()
    }

    func testAgentErrorResponse() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"error":{"code":-32600,"message":"Invalid request"}}'
            break
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        do {
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            XCTFail("Should have thrown agent error")
        } catch let error as ClientError {
            if case .agentError(let rpcError) = error {
                XCTAssertEqual(rpcError.code, -32600)
                XCTAssertEqual(rpcError.message, "Invalid request")
            } else {
                XCTFail("Expected agent error, got: \(error)")
            }
        }

        await client.terminate()
    }

    func testSendPromptRequest() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')

            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"session-123"}}'
            elif [ "$method" = "session/prompt" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)

        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)

        let response = try await client.sendPrompt(
            sessionId: session.sessionId,
            content: [.text(TextContent(text: "Hello, agent!"))]
        )

        XCTAssertEqual(response.stopReason, .endTurn)

        await client.terminate()
    }
}

// MARK: - Delegate Tests

final class ACPDelegateTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testFileSystemDelegateReadFile() async throws {
        // Create a test file
        let testFilePath = tempDir.appendingPathComponent("test.txt").path
        try "Hello, World!".write(toFile: testFilePath, atomically: true, encoding: .utf8)

        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(testFilePath, sessionId: "s1", line: nil, limit: nil)

        XCTAssertEqual(response.content, "Hello, World!")
    }

    func testFileSystemDelegateWriteFile() async throws {
        let testFilePath = tempDir.appendingPathComponent("output.txt").path

        let delegate = FileSystemDelegate()
        _ = try await delegate.handleFileWriteRequest(testFilePath, content: "Test content", sessionId: "s1")

        let writtenContent = try String(contentsOfFile: testFilePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, "Test content")
    }

    func testFileSystemDelegateReadWithLineOffset() async throws {
        let testFilePath = tempDir.appendingPathComponent("multiline.txt").path
        let content = (1...10).map { "Line \($0)" }.joined(separator: "\n")
        try content.write(toFile: testFilePath, atomically: true, encoding: .utf8)

        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(testFilePath, sessionId: "s1", line: 5, limit: 2)

        // Should read lines 5-6 (0-indexed from line 5, limit 2)
        XCTAssertTrue(response.content.contains("Line 5") || response.content.contains("Line 6"))
    }

    func testFileSystemDelegateReadNonexistentFile() async throws {
        let delegate = FileSystemDelegate()

        do {
            _ = try await delegate.handleFileReadRequest("/nonexistent/path/file.txt", sessionId: "s1", line: nil, limit: nil)
            XCTFail("Should have thrown error for nonexistent file")
        } catch {
            // Expected
        }
    }
}

// MARK: - Integration Tests for Types

final class ACPTypeIntegrationTests: XCTestCase {

    func testFullJSONRPCMessageRoundTrip() throws {
        let request = JSONRPCRequest(
            id: .number(42),
            method: "session/prompt",
            params: AnyCodable([
                "sessionId": "session-123",
                "prompt": [
                    ["type": "text", "text": "Hello, agent!"]
                ]
            ] as [String: Any])
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(request)
        let decoded = try decoder.decode(JSONRPCRequest.self, from: data)

        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.method, request.method)
    }

    func testSessionUpdateNotificationRoundTrip() throws {
        let notification = SessionUpdateNotification(
            sessionId: SessionId("session-123"),
            update: .agentMessageChunk(.text(TextContent(text: "Hello!")))
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(notification)
        let decoded = try decoder.decode(SessionUpdateNotification.self, from: data)

        XCTAssertEqual(decoded.sessionId.value, "session-123")
        XCTAssertEqual(decoded.update.sessionUpdateType, "agent_message_chunk")
    }

    func testToolCallUpdateRoundTrip() throws {
        let update = ToolCallUpdate(
            toolCallId: "tc-1",
            status: .completed,
            title: "Read File",
            kind: .read,
            content: [.content(.text(TextContent(text: "file contents")))],
            locations: [ToolLocation(path: "/tmp/file.txt", line: 10)]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(update)
        let decoded = try decoder.decode(ToolCallUpdate.self, from: data)

        XCTAssertEqual(decoded.toolCallId, "tc-1")
        XCTAssertEqual(decoded.status, .completed)
        XCTAssertEqual(decoded.title, "Read File")
        XCTAssertEqual(decoded.kind, .read)
        XCTAssertEqual(decoded.locations?.first?.path, "/tmp/file.txt")
    }

    func testComplexSessionUpdateParsing() throws {
        let json = """
        {
            "sessionUpdate": "tool_call",
            "toolCallId": "call-abc-123",
            "title": "Searching for files",
            "kind": "search",
            "status": "in_progress",
            "content": [
                {"type": "content", "content": {"type": "text", "text": "Searching..."}}
            ],
            "locations": [
                {"path": "/project/src", "line": null}
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let update = try JSONDecoder().decode(SessionUpdate.self, from: data)

        XCTAssertEqual(update.toolCallId, "call-abc-123")
        XCTAssertEqual(update.title, "Searching for files")
        XCTAssertEqual(update.kind, .search)
        XCTAssertEqual(update.status, .inProgress)
    }

    func testInitializeResponseDecoding() throws {
        let json = """
        {
            "protocolVersion": 1,
            "agentCapabilities": {
            },
            "agentInfo": {
                "name": "TestAgent",
                "version": "2.0.0",
                "title": "Test Agent"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(InitializeResponse.self, from: data)

        XCTAssertEqual(response.protocolVersion, 1)
        XCTAssertEqual(response.agentInfo?.name, "TestAgent")
        XCTAssertEqual(response.agentInfo?.version, "2.0.0")
    }

    func testNewSessionResponseDecoding() throws {
        let json = """
        {
            "sessionId": "session-456",
            "modes": {
                "currentModeId": "code",
                "availableModes": [
                    {"id": "code", "name": "Code Mode"},
                    {"id": "chat", "name": "Chat Mode"}
                ]
            },
            "models": {
                "currentModelId": "gpt-4",
                "availableModels": [
                    {"modelId": "gpt-4", "name": "GPT-4"},
                    {"modelId": "gpt-3.5", "name": "GPT-3.5"}
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(NewSessionResponse.self, from: data)

        XCTAssertEqual(response.sessionId.value, "session-456")
        XCTAssertEqual(response.modes?.currentModeId, "code")
        XCTAssertEqual(response.modes?.availableModes.count, 2)
        XCTAssertEqual(response.models?.currentModelId, "gpt-4")
    }

    func testRequestPermissionRequestWithAllFields() throws {
        let json = """
        {
            "message": "Run npm install",
            "sessionId": "session-123",
            "options": [
                {"kind": "allow", "name": "Allow", "optionId": "opt-allow"},
                {"kind": "deny", "name": "Deny", "optionId": "opt-deny"}
            ],
            "toolCall": {
                "toolCallId": "tc-123",
                "rawInput": {"command": "npm install"}
            }
        }
        """

        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(RequestPermissionRequest.self, from: data)

        XCTAssertEqual(request.message, "Run npm install")
        XCTAssertEqual(request.sessionId?.value, "session-123")
        XCTAssertEqual(request.options?.count, 2)
        XCTAssertEqual(request.toolCall?.toolCallId, "tc-123")
    }
}
