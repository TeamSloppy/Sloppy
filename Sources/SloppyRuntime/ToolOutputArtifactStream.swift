import Foundation
import Protocols

/// Pull-based and single-consumer: a slow reader never accumulates a producer-side buffer.
public struct ToolOutputArtifactStream: AsyncSequence, Sendable {
    public typealias Element = Data
    private let reader: ToolOutputArtifactReader

    init(store: AgentSessionFileStore, artifact: AgentToolOutputArtifact) throws {
        reader = try ToolOutputArtifactReader(store: store, artifact: artifact)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate let reader: ToolOutputArtifactReader
        private let id = UUID()
        fileprivate init(reader: ToolOutputArtifactReader) { self.reader = reader }
        public mutating func next() async throws -> Data? { try await reader.next(id: id) }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(reader: reader) }
}

fileprivate actor ToolOutputArtifactReader {
    private let directory: URL
    private let handle: FileHandle
    private var consumer: UUID?
    private var closed = false

    init(store: AgentSessionFileStore, artifact: AgentToolOutputArtifact) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-output-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let file = directory.appendingPathComponent("output.json")
            try store.exportToolOutputArtifact(artifact, to: file)
            handle = try FileHandle(forReadingFrom: file)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
        self.directory = directory
    }

    func next(id: UUID) throws -> Data? {
        guard consumer == nil || consumer == id else { throw AgentSessionFileStore.StoreError.invalidPayload }
        consumer = id
        if Task.isCancelled { close(); throw CancellationError() }
        guard !closed else { return nil }
        do {
            let bytes = try handle.read(upToCount: 65_536) ?? Data()
            if bytes.isEmpty { close(); return nil }
            return bytes
        } catch { close(); throw error }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        try? handle.close()
        try? FileManager.default.removeItem(at: directory)
    }
    deinit {
        try? handle.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
