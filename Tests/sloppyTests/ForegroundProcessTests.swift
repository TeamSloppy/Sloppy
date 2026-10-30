import Foundation
import Protocols
import Testing
@testable import sloppy
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if !os(Windows)
@Suite("Foreground command input and process state")
struct ForegroundProcessTests {
    @Test("commands without explicit stdin receive EOF")
    func defaultInputIsEOF() async throws {
        let result = try await runForegroundProcess(
            command: "/bin/sh", arguments: ["-c", "if read value; then printf unexpected; else printf eof; fi"],
            cwd: nil, timeoutMs: 3_000, maxOutputBytes: 4096
        )
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        #expect(result.asObject?["stdout"]?.asString == "eof")
        #expect(result.asObject?["timedOut"]?.asBool == false)
    }

    @Test("explicit stdin retains every byte, including binary data larger than a pipe buffer")
    func explicitInputIsPreserved() async throws {
        let fixture = try CodingHarnessFixture()
        defer { fixture.cleanup() }
        let input = Data((0..<131_072).map { UInt8($0 % 256) })
        let output = fixture.root.appendingPathComponent("input.bin")
        let result = try await runForegroundProcess(
            command: "/bin/sh", arguments: ["-c", "cat > input.bin; printf received"],
            cwd: fixture.root, timeoutMs: 5_000, maxOutputBytes: 4096, standardInput: input
        )
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        #expect(result.asObject?["stdout"]?.asString == "received")
        #expect(try Data(contentsOf: output) == input)
    }

    @Test("empty explicit stdin closes its pipe")
    func emptyExplicitInputIsEOF() async throws {
        let result = try await runForegroundProcess(
            command: "/bin/cat", arguments: [], cwd: nil, timeoutMs: 3_000,
            maxOutputBytes: 4096, standardInput: Data()
        )
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        #expect(result.asObject?["stdout"]?.asString == "")
        #expect(result.asObject?["timedOut"]?.asBool == false)
    }

    @Test("runtime.exec preserves pipelines, file redirects and heredocs")
    func shellInputSources() async throws {
        let fixture = try CodingHarnessFixture()
        defer { fixture.cleanup() }
        try "file input\n".write(to: fixture.root.appendingPathComponent("input.txt"), atomically: true, encoding: .utf8)
        let result = await RuntimeExecTool().invoke(arguments: [
            "command": .string("/bin/sh"), "arguments": .array([.string("-c"), .string("""
            printf 'pipeline input\n' | tr 'a-z' 'A-Z'
            cat < input.txt
            cat <<'EOF'
            heredoc input
            EOF
            """)]),
            "timeoutMs": .number(5_000)
        ], context: fixture.context())
        #expect(result.ok)
        #expect(result.data?.asObject?["exitCode"]?.asInt == 0)
        #expect(result.data?.asObject?["stdout"]?.asString == "PIPELINE INPUT\nfile input\nheredoc input\n")
    }

    @Test("SloppyNode invoke --stdin still receives a real JSON request")
    func sloppyNodeExplicitInput() async throws {
        var anchors = [CommandLine.arguments[0]]
        if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), CommandLine.arguments.indices.contains(index + 1) {
            anchors.append(CommandLine.arguments[index + 1])
        }
        var executable: URL?
        for anchor in anchors {
            var directory = URL(fileURLWithPath: anchor).deletingLastPathComponent()
            for _ in 0..<5 {
                let candidate = directory.appendingPathComponent("SloppyNode")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { executable = candidate; break }
                directory.deleteLastPathComponent()
            }
            if executable != nil { break }
        }
        let node = try #require(executable, "Build the SloppyNode product before running this integration test")
        let input = try JSONEncoder().encode(NodeActionRequest(action: .status))
        let result = try await runForegroundProcess(
            command: node.path, arguments: ["invoke", "--stdin", "--node-id", "stdin-regression"],
            cwd: nil, timeoutMs: 10_000, maxOutputBytes: 16_384, standardInput: input
        )
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        let stdout = try #require(result.asObject?["stdout"]?.asString)
        let response = try JSONDecoder().decode(NodeActionResponse.self, from: Data(stdout.utf8))
        #expect(response.ok)
        #expect(response.data?.asObject?["nodeId"]?.asString == "stdin-regression")
    }

    @Test("OS stops are observed without resuming or reaping the child")
    func observesStoppedProcess() async throws {
        let childFlag = "SLOPPY_TEST_PROCESS_STOP_CHILD"
        if ProcessInfo.processInfo.environment[childFlag] != "1" {
            // Hundreds of parallel Core fixtures can starve this runner's task
            // executor past a command deadline. Observe OS signals in an isolated
            // runner so the test measures process control rather than suite load.
            try await runIsolatedForegroundTest(filter: "observesStoppedProcess", childFlag: childFlag)
            return
        }
        let updates = AsyncStream<(ForegroundProcessState, Int32)>.makeStream()
        let run = Task {
            defer { updates.continuation.finish() }
            return try await runForegroundProcess(
                command: "/bin/sh", arguments: ["-c", "kill -STOP $$; sleep 0.5; printf resumed"],
                cwd: nil, timeoutMs: 5_000, maxOutputBytes: 4096,
                progress: { state, pid in _ = updates.continuation.yield((state, pid)) }
            )
        }
        defer { run.cancel() }
        var observedStop = false
        for await (state, pid) in updates.stream where state == .stopped {
            observedStop = true
            try await Task.sleep(for: .milliseconds(100))
            #expect(foregroundProcessState(pid) == .stopped)
            // Only the test resumes its own child; production is observational.
            #expect(kill(pid, SIGCONT) == 0)
            break
        }
        let result = try await run.value
        #expect(observedStop)
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        #expect(result.asObject?["stdout"]?.asString == "resumed")
    }
}

#if canImport(Darwin)
@Test("foreground exec does not inherit a TTY even when its parent has one")
func foregroundExecDoesNotInheritTerminal() async throws {
    let childFlag = "SLOPPY_TEST_FOREGROUND_TTY_CHILD"
    if ProcessInfo.processInfo.environment[childFlag] == "1" {
        #expect(isatty(STDIN_FILENO) == 1)
        let result = try await runForegroundProcess(
            command: "/bin/sh",
            arguments: ["-c", "if [ -t 0 ]; then printf inherited-terminal; elif read value; then printf unexpected; else printf eof; fi"],
            cwd: nil, timeoutMs: 3_000, maxOutputBytes: 4096
        )
        #expect(result.asObject?["stdout"]?.asString == "eof")
        #expect(result.asObject?["exitCode"]?.asInt == 0)
        return
    }

    var master: Int32 = -1
    var slave: Int32 = -1
    try #require(openpty(&master, &slave, nil, nil, nil) == 0)
    let terminalInput = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
    defer { close(master); try? terminalInput.close() }
    try await runIsolatedForegroundTest(
        filter: "foregroundExecDoesNotInheritTerminal", childFlag: childFlag, standardInput: terminalInput
    )
}
#endif

private func runIsolatedForegroundTest(filter: String, childFlag: String, standardInput: FileHandle? = nil) async throws {
    let fixture = try CodingHarnessFixture()
    defer { fixture.cleanup() }
    let outputURL = fixture.root.appendingPathComponent("child.log")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    defer { try? output.close() }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    var arguments: [String] = []
    if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), CommandLine.arguments.indices.contains(index + 1) {
        arguments += ["--test-bundle-path", CommandLine.arguments[index + 1]]
    }
    child.arguments = arguments + ["--testing-library", "swift-testing", "--filter", filter]
    child.environment = ProcessInfo.processInfo.environment.merging([childFlag: "1"]) { _, new in new }
    child.standardInput = standardInput ?? FileHandle.nullDevice
    child.standardOutput = output
    child.standardError = output
    try child.run()
    let timedOut = await waitForProcessExitOrTimeout(process: child, timeoutMs: 20_000)
    if timedOut { await terminateProcess(child) }
    let log = try String(contentsOf: outputURL, encoding: .utf8)
    #expect(!timedOut, "Isolated \(filter) timed out: \(log)")
    #expect(child.terminationStatus == 0, "Isolated \(filter) failed: \(log)")
}
#endif
