import XCTest
@testable import ACP

final class StdinTransportTests: XCTestCase {
    func testSendWritesWhileInputReaderIsWaitingForMoreData() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = StdinTransport(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        await transport.start()
        defer {
            Task { await transport.close() }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForWriting.close()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await transport.send(Data("{\"jsonrpc\":\"2.0\"}".utf8))
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 500_000_000)
                throw TestTimeoutError()
            }

            try await group.next()
            group.cancelAll()
        }

        try output.fileHandleForWriting.close()
        let data = try output.fileHandleForReading.read(upToCount: 1024)
        XCTAssertEqual(String(data: data ?? Data(), encoding: .utf8), "{\"jsonrpc\":\"2.0\"}\n")
    }
}

private struct TestTimeoutError: Error {}
