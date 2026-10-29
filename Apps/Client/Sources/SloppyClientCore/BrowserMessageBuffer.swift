import Foundation

/// Some FoundationNetworking/libcurl versions deliver a large WebSocket text message in chunks.
/// CDP messages are JSON objects; assemble complete objects without repeatedly decoding partial PNG data.
struct BrowserMessageBuffer {
    private var bytes = Data()
    private var depth = 0
    private var inString = false
    private var escaped = false

    mutating func append(_ chunk: Data) throws -> [Data] {
        var messages: [Data] = []
        for byte in chunk {
            if bytes.isEmpty, byte == 10 || byte == 13 || byte == 32 { continue }
            guard bytes.count < 32 * 1024 * 1024 else { throw WorkspaceBrowserError.command("Browser response exceeded 32 MiB.") }
            bytes.append(byte)
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else {
                if byte == 34 { inString = true }
                else if byte == 123 || byte == 91 { depth += 1 }
                else if byte == 125 || byte == 93 { depth -= 1 }
                guard depth >= 0 else { throw WorkspaceBrowserError.command("Invalid browser response.") }
                if depth == 0 {
                    messages.append(bytes)
                    bytes = Data()
                }
            }
        }
        return messages
    }
}
