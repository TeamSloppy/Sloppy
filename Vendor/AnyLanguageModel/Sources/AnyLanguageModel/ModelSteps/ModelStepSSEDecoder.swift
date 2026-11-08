import Foundation

/// Bounded UTF-8 framing shared by provider codecs; payload semantics stay in each codec.
public struct StepSSEDecoder {
    public init() {}
    private var bytes = Data()
    private var lines = [String]()
    private var eventBytes = 0
    private let limit = 8 * 1024 * 1024

    public mutating func consume(_ chunk: Data) throws -> [String] {
        bytes.append(chunk)
        var frames = [String]()
        while let newline = bytes.firstIndex(of: 0x0A) {
            var line = Data(bytes[..<newline])
            bytes.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if let frame = try consumeLine(try text(line)) { frames.append(frame) }
        }
        guard bytes.count <= limit else { throw oversized() }
        return frames
    }

    public mutating func finish() throws -> [String] {
        var frames = [String]()
        if !bytes.isEmpty {
            if let frame = try consumeLine(try text(bytes)) { frames.append(frame) }
            bytes.removeAll()
        }
        if let frame = try consumeLine("") { frames.append(frame) }
        return frames
    }

    private mutating func consumeLine(_ line: String) throws -> String? {
        if line.hasPrefix("data:") {
            let value = String(line.dropFirst(5))
            lines.append(value.hasPrefix(" ") ? String(value.dropFirst()) : value)
            eventBytes += value.utf8.count + 1
            guard eventBytes <= limit else { throw oversized() }
            return nil
        }
        guard line.isEmpty, !lines.isEmpty else { return nil }
        let frame = lines.joined(separator: "\n")
        lines.removeAll(keepingCapacity: true)
        eventBytes = 0
        return frame
    }

    private func text(_ data: Data) throws -> String {
        guard data.count <= limit else { throw oversized() }
        guard let text = String(data: data, encoding: .utf8) else {
            throw LanguageModelStepFailure(category: .protocolViolation, code: "invalid_sse_utf8",
                message: "SSE data is not valid UTF-8.", stage: .streaming)
        }
        return text
    }

    private func oversized() -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: "sse_frame_too_large",
            message: "An SSE frame exceeded 8 MiB.", stage: .streaming)
    }
}
