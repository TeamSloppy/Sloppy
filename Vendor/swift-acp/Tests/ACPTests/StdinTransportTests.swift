import Foundation
import Testing
@testable import ACP

@Suite("ACP stdin transport")
struct StdinTransportTests {
    @Test("Responds after an asynchronous handler while stdin remains open")
    func respondsWithOpenInput() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = StdinTransport(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        let responses = AsyncStream<Data>.makeStream()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                responses.continuation.finish()
            } else {
                responses.continuation.yield(data)
            }
        }
        await transport.start()
        defer {
            Task { await transport.close() }
            try? input.fileHandleForWriting.close()
            output.fileHandleForReading.readabilityHandler = nil
            try? output.fileHandleForWriting.close()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            defer {
                group.cancelAll()
                try? input.fileHandleForWriting.close()
            }
            group.addTask {
                var messages = transport.messages.makeAsyncIterator()
                // Fragmented and coalesced frames use the real pipe parser.
                try input.fileHandleForWriting.write(contentsOf: Data("{\"id\":".utf8))
                try input.fileHandleForWriting.write(contentsOf: Data("1}\n{\"id\":2}\n".utf8))
                #expect(await messages.next() == Data("{\"id\":1}".utf8))
                #expect(await messages.next() == Data("{\"id\":2}".utf8))
                // Model/account loading suspends Sloppy's initialize handler too.
                try await Task.sleep(for: .milliseconds(100))
                try await transport.send(Data("{\"id\":1,\"result\":{}}".utf8))
                var received = Data()
                for await chunk in responses.stream {
                    received.append(chunk)
                    if received.last == 10 { break }
                }
                #expect(received == Data("{\"id\":1,\"result\":{}}\n".utf8))
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw TestTimeoutError()
            }

            try await group.next()
        }
        await transport.close()
    }
}

private struct TestTimeoutError: Error {}
