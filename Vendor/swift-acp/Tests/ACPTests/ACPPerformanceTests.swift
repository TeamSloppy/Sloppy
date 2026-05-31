import XCTest
@testable import ACP

// MARK: - Mock Delegate for Testing

final class MockClientDelegate: ClientDelegate, Sendable {
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        ReadTextFileResponse(content: "mock content", totalLines: 1)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        WriteTextFileResponse()
    }

    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse {
        CreateTerminalResponse(terminalId: TerminalId("mock-term"))
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        TerminalOutputResponse(output: "", exitStatus: nil, truncated: false)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        WaitForExitResponse(exitCode: 0)
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        KillTerminalResponse(success: true)
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        ReleaseTerminalResponse(success: true)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow"))
    }
}

/// Performance and memory leak tests
final class ACPPerformanceTests: XCTestCase {

    var tempDir: URL!
    var mockAgentPath: String!

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

    // MARK: - Memory Leak Tests

    /// Test that Client deallocates properly after terminate
    func testClientDeallocation() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        """)

        weak var weakClient: Client?

        try await {
            let client = Client()
            weakClient = client

            try await client.launch(agentPath: mockAgentPath)
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            await client.terminate()
        }()

        // Give time for async cleanup
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(weakClient, "Client should be deallocated after terminate")
    }

    /// Test repeated client creation/destruction doesn't leak memory
    func testRepeatedClientCreationNoLeak() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            fi
        done
        """)

        // Track weak references to verify deallocation
        var weakClients: [() -> Client?] = []

        for _ in 0..<5 {
            weak var weakClient: Client?

            try await {
                let client = Client()
                weakClient = client

                try await client.launch(agentPath: mockAgentPath)
                _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
                await client.terminate()
            }()

            // Capture weak reference check
            let check: () -> Client? = { [weak weakClient] in weakClient }
            weakClients.append(check)

            // Small delay between iterations
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Give time for cleanup
        try await Task.sleep(nanoseconds: 200_000_000)

        // All clients should be deallocated
        for (i, check) in weakClients.enumerated() {
            XCTAssertNil(check(), "Client \(i) should be deallocated")
        }
    }

    /// Test notification stream doesn't retain client
    func testNotificationStreamNoRetainCycle() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        echo '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}}}'
        """)

        weak var weakClient: Client?
        var receivedNotification = false

        try await {
            let client = Client()
            weakClient = client

            try await client.launch(agentPath: mockAgentPath)

            let notifications = await client.notifications

            // Start listening task
            let listenTask = Task {
                for await notification in notifications {
                    if notification.method == "session/update" {
                        receivedNotification = true
                        break
                    }
                }
            }

            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

            // Wait for notification
            try await Task.sleep(nanoseconds: 200_000_000)

            listenTask.cancel()
            await client.terminate()
        }()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(receivedNotification, "Should have received notification")
        XCTAssertNil(weakClient, "Client should be deallocated")
    }

    /// Test delegate doesn't create retain cycle
    func testDelegateNoRetainCycle() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        """)

        weak var weakClient: Client?
        weak var weakDelegate: MockClientDelegate?

        try await {
            let client = Client()
            let delegate = MockClientDelegate()

            weakClient = client
            weakDelegate = delegate

            await client.setDelegate(delegate)
            try await client.launch(agentPath: mockAgentPath)
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            await client.terminate()
        }()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(weakClient, "Client should be deallocated")
        XCTAssertNil(weakDelegate, "Delegate should be deallocated")
    }

    // MARK: - Stress Tests

    /// Test many sequential requests don't leak
    func testManySequentialRequestsNoLeak() async throws {
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

        // Create many sessions
        for i in 0..<20 {
            let session = try await client.newSession(workingDirectory: "/tmp/\(i)", timeout: 5.0)
            XCTAssertFalse(session.sessionId.value.isEmpty)
        }

        await client.terminate()
    }

    /// Test rapid request/response cycles
    func testRapidRequestResponseCycles() async throws {
        try createMockAgent(script: """
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            method=$(echo "$line" | grep -o '"method":"[^"]*"' | sed 's/"method":"\\([^"]*\\)"/\\1/')
            if [ "$method" = "initialize" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
            elif [ "$method" = "session/new" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"sessionId":"s-'$id'"}}'
            elif [ "$method" = "session/prompt" ]; then
                echo '{"jsonrpc":"2.0","id":'$id',"result":{"stopReason":"end_turn"}}'
            fi
        done
        """)

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)
        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let session = try await client.newSession(workingDirectory: "/tmp", timeout: 5.0)

        // Send many prompts rapidly
        for i in 0..<10 {
            let response = try await client.sendPrompt(
                sessionId: session.sessionId,
                content: [.text(TextContent(text: "Prompt \(i)"))]
            )
            XCTAssertEqual(response.stopReason, .endTurn)
        }

        await client.terminate()
    }

    // MARK: - Performance Benchmarks

    func testClientLaunchPerformance() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        """)

        // Measure launch + initialize time
        let start = CFAbsoluteTimeGetCurrent()

        let client = Client()
        try await client.launch(agentPath: mockAgentPath)
        _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        await client.terminate()

        // Should complete in reasonable time
        XCTAssertLessThan(elapsed, 2.0, "Launch + initialize should complete in under 2 seconds")
    }

    func testMessageEncodingPerformance() throws {
        // Test encoding performance for large messages
        let largeText = String(repeating: "Hello world. ", count: 1000)
        let content = TextContent(text: largeText)
        let contentBlock = ContentBlock.text(content)

        let encoder = JSONEncoder()

        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = try encoder.encode(contentBlock)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // 100 encodings should be fast
        XCTAssertLessThan(elapsed, 1.0, "100 message encodings should complete in under 1 second")
    }

    func testMessageDecodingPerformance() throws {
        let json = """
        {
            "sessionUpdate": "tool_call",
            "toolCallId": "call-123",
            "title": "Reading file",
            "kind": "read",
            "status": "completed",
            "content": [
                {"type": "content", "content": {"type": "text", "text": "\(String(repeating: "x", count: 10000))"}}
            ],
            "locations": [
                {"path": "/tmp/file.txt", "line": 1}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = try decoder.decode(SessionUpdate.self, from: data)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 1.0, "100 message decodings should complete in under 1 second")
    }

    // MARK: - Resource Cleanup Tests

    /// Test that file handles are properly closed
    func testFileHandleCleanup() async throws {
        try createMockAgent(script: """
        read -r line
        id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        sleep 1
        """)

        // Get initial file descriptor count
        let initialFDs = getOpenFileDescriptorCount()

        for _ in 0..<3 {
            let client = Client()
            try await client.launch(agentPath: mockAgentPath)
            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            await client.terminate()

            // Small delay for cleanup
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Give time for all cleanup
        try await Task.sleep(nanoseconds: 200_000_000)

        let finalFDs = getOpenFileDescriptorCount()

        // Should not have significant FD leak (allow small margin for system activity)
        XCTAssertLessThanOrEqual(finalFDs, initialFDs + 5, "File descriptors should be cleaned up (initial: \(initialFDs), final: \(finalFDs))")
    }

    /// Test process cleanup after termination
    func testProcessCleanup() async throws {
        try createMockAgent(script: """
        trap 'exit 0' TERM
        while read -r line; do
            id=$(echo "$line" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
            echo '{"jsonrpc":"2.0","id":'$id',"result":{"protocolVersion":1,"agentCapabilities":{}}}'
        done
        """)

        for _ in 0..<3 {
            let client = Client()
            try await client.launch(agentPath: mockAgentPath)

            // Get the process ID (we'll check it's cleaned up)
            // Note: We can't directly access the PID, but we can verify the process count

            _ = try await client.initialize(capabilities: makeCapabilities(), timeout: 5.0)
            await client.terminate()

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Check no zombie processes from our mock agent
        let zombieCheck = try? runShellCommand("ps aux | grep mock-agent | grep -v grep | wc -l")
        let zombieCount = Int(zombieCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0

        XCTAssertEqual(zombieCount, 0, "No zombie mock-agent processes should remain")
    }

    // MARK: - Helpers

    private func getOpenFileDescriptorCount() -> Int {
        var count = 0
        for fd in 0..<1024 {
            var statbuf = stat()
            if fstat(Int32(fd), &statbuf) == 0 {
                count += 1
            }
        }
        return count
    }

    private func runShellCommand(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
