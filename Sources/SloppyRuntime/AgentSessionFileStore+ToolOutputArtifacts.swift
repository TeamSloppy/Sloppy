import Foundation
import PluginSDK
import Protocols

public struct ToolOutputArtifactChunk: Sendable {
    public let data: Data
    public let offset: Int
    public let totalBytes: Int
    public var nextOffset: Int? { offset + data.count < totalBytes ? offset + data.count : nil }
}

extension AgentSessionFileStore {
    /// Separate from user uploads: no base64 expansion or 25 MiB upload ceiling.
    public func persistToolOutputArtifact(agentID: String, sessionID: String, callEventID: String, bytes: Data) throws -> AgentToolOutputArtifact {
        try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let agentID = try normalizedAgentID(agentID)
            let sessionID = try normalizedSessionID(sessionID)
            guard !callEventID.isEmpty, !bytes.isEmpty,
                  let directory = assetsDirectoryURL(agentID: agentID, sessionID: sessionID),
                  let agent = resolvedAgentDirectoryURL(agentID: agentID) else { throw StoreError.invalidPayload }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID().uuidString.lowercased()
            let file = directory.appendingPathComponent("tool-output-" + id + ".json")
            try bytes.write(to: file, options: .atomic)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.synchronize()
            let attachment = AgentAttachment(id: id, name: "tool-output.json", mimeType: "application/json",
                sizeBytes: bytes.count, relativePath: AgentSessionPathResolver.relativePath(from: agent, to: file))
            var artifact = AgentToolOutputArtifact(agentId: agentID, sessionId: sessionID, callEventId: callEventID,
                attachment: attachment, sha256: ContentDigest.sha256(bytes))
            artifact.schemaVersion = 2
            return artifact
        }
    }

    private func toolOutputURL(_ artifact: AgentToolOutputArtifact) throws -> URL {
        let agentID = try normalizedAgentID(artifact.agentId)
        let sessionID = try normalizedSessionID(artifact.sessionId)
        guard (1...2).contains(artifact.schemaVersion), artifact.format == "tool_invocation_result_v1",
              artifact.attachment.mimeType == "application/json", artifact.attachment.sizeBytes > 0,
              let assets = assetsDirectoryURL(agentID: agentID, sessionID: sessionID)?.resolvingSymlinksInPath().standardizedFileURL,
              let file = try resolveAttachmentFileURL(agentID: agentID, attachment: artifact.attachment)?.resolvingSymlinksInPath().standardizedFileURL,
              file.path.hasPrefix(assets.path + "/") else { throw StoreError.invalidPayload }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, values.fileSize == artifact.attachment.sizeBytes else { throw StoreError.invalidPayload }
        return file
    }

    public func verifyToolOutputArtifact(_ artifact: AgentToolOutputArtifact) throws {
        let file = try toolOutputURL(artifact)
        guard try ContentDigest.sha256(fileAt: file) == artifact.sha256 else { throw StoreError.invalidPayload }
    }

    public func readToolOutputArtifact(_ artifact: AgentToolOutputArtifact) throws -> ToolInvocationResult {
        let bytes = try readInputAttachment(agentID: artifact.agentId, sessionID: artifact.sessionId, attachment: artifact.attachment)
        guard ContentDigest.sha256(bytes) == artifact.sha256 else { throw StoreError.invalidPayload }
        return try JSONDecoder().decode(ToolInvocationResult.self, from: bytes)
    }

    /// The returned bytes participate in this exact verification pass; no second mutable-file read.
    public func readToolOutputArtifactChunk(_ artifact: AgentToolOutputArtifact, offset: Int, limit: Int = 65_536) throws -> ToolOutputArtifactChunk {
        guard offset >= 0, offset <= artifact.attachment.sizeBytes, (1...1_048_576).contains(limit) else { throw StoreError.invalidPayload }
        let file = try toolOutputURL(artifact)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = ContentDigest.SHA256()
        var position = 0
        var result = Data()
        let end = offset + min(limit, artifact.attachment.sizeBytes - offset)
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(chunk)
            let lower = max(offset, position), upper = min(end, position + chunk.count)
            if lower < upper { result.append(chunk[(chunk.startIndex + lower - position)..<(chunk.startIndex + upper - position)]) }
            position += chunk.count
        }
        guard position == artifact.attachment.sizeBytes, hasher.finalize() == artifact.sha256 else { throw StoreError.invalidPayload }
        return .init(data: result, offset: offset, totalBytes: position)
    }

    /// Publish a byte-exact export only after hashing the same chunks written to its staging file.
    public func exportToolOutputArtifact(_ artifact: AgentToolOutputArtifact, to destination: URL) throws {
        let source = try toolOutputURL(artifact)
        guard destination.standardizedFileURL.resolvingSymlinksInPath() != source else { throw StoreError.invalidPayload }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".sloppy-export-" + UUID().uuidString)
        guard fileManager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw StoreError.invalidPayload }
        defer { try? fileManager.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var hasher = ContentDigest.SHA256()
        var size = 0
        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(chunk); size += chunk.count
            try output.write(contentsOf: chunk)
        }
        guard size == artifact.attachment.sizeBytes, hasher.finalize() == artifact.sha256 else { throw StoreError.invalidPayload }
        try output.synchronize(); try output.close()
        // Do not replace an existing user file, including on export retry.
        try fileManager.moveItem(at: temporary, to: destination)
    }

    /// Only generated, old, unreferenced files are eligible. All canonical attachments remain roots.
    @discardableResult
    public func cleanupToolOutputArtifacts(agentID: String, sessionID: String, olderThan cutoff: Date) throws -> Int {
        return try withLock {
            let ownership = try retainJournalOwnership()
            defer { withExtendedLifetime(ownership) {} }
            let journal = URL(fileURLWithPath: try sessionFilePath(agentID: agentID, sessionID: sessionID))
            let lease = try FileOwnershipLease.acquire(at: journal.appendingPathExtension("owner.lock"))
            defer { lease.release() }
            guard cutoff <= Date().addingTimeInterval(-3_600),
                  let assets = assetsDirectoryURL(agentID: agentID, sessionID: sessionID) else { throw StoreError.invalidPayload }
            let attachments = try attachmentReferences(agentID: agentID, sessionID: sessionID)
            let keep = Set(try attachments.compactMap { try resolveAttachmentFileURL(agentID: agentID, attachment: $0)?.standardizedFileURL.path })
            guard fileManager.fileExists(atPath: assets.path) else { return 0 }
            var removed = 0
            for file in try fileManager.contentsOfDirectory(at: assets, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) {
                guard file.lastPathComponent.hasPrefix("tool-output-"), file.pathExtension == "json",
                      !keep.contains(file.standardizedFileURL.path) else { continue }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let modified = values.contentModificationDate, modified < cutoff else { continue }
                try fileManager.removeItem(at: file); removed += 1
            }
            return removed
        }
    }
}
