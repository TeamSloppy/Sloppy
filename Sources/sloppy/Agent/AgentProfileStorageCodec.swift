import Foundation
import Protocols

/// Storage-only discriminator: old Core fails decoding before it can resume this agent.
/// Public API DTOs retain native/acp. The marker survives rollback while unified journals may exist.
enum AgentProfileStorageCodec {
    enum CodecError: Error { case invalidProfile, protectionMissing }
    private static let protectionVersions = 2...8
    // Synchronous filesystem APIs share this narrow transaction boundary across catalog instances.
    // Runtime scheduling and state remain actor-isolated.
    private static let operationLock = NSRecursiveLock()

    static func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try operation()
    }

    static func normalized(_ data: Data) throws -> Data {
        var object = try dictionary(data)
        guard var runtime = object["runtime"] as? [String: Any] else { return data }
        guard try protectionVersion(runtime) > 0 else { return data }
        guard let underlying = runtime["storageRuntimeType"] as? String,
              AgentRuntimeType(rawValue: underlying) != nil,
              let engine = runtime["nativeEngine"] as? String, AgentNativeEngine(rawValue: engine) != nil else {
            throw CodecError.invalidProfile
        }
        runtime["type"] = underlying
        runtime.removeValue(forKey: "storageRuntimeType")
        object["runtime"] = runtime
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func write(_ data: Data, to url: URL, companion: URL, forceProtection: Bool = false, minimumJournalVersion: Int = 2) throws {
        try withLock {
            guard protectionVersions.contains(minimumJournalVersion) else { throw CodecError.invalidProfile }
            var object = try dictionary(data)
            let enabled = (object["runtime"] as? [String: Any])?["type"] as? String == AgentRuntimeType.native.rawValue
            let existing = try protectionVersion(at: url)
            let companionVersion = try protectionVersion(at: companion)
            let evidenceVersion = (object["runtime"] as? [String: Any])?["evidencePolicyVersion"] as? Int
            let required = max(existing, companionVersion, enabled || forceProtection ? max(minimumJournalVersion, evidenceVersion == 2 ? 6 : 2) : 0)
            if required > 0 {
                guard var runtime = object["runtime"] as? [String: Any],
                      let kind = runtime["type"] as? String, AgentRuntimeType(rawValue: kind) != nil else {
                    throw CodecError.invalidProfile
                }
                runtime["storageRuntimeType"] = kind
                runtime["type"] = "native_v\(required)"
                runtime["nativeEngine"] = runtime["nativeEngine"] ?? AgentNativeEngine.legacy.rawValue
                object["runtime"] = runtime
            }
            var payload = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            payload.append(0x0A)
            try payload.write(to: url, options: .atomic)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.synchronize()
        }
    }

    static func verify(metadata: URL, config: URL, minimumJournalVersion: Int = 2) throws {
        try withLock {
            guard protectionVersions.contains(minimumJournalVersion) else { throw CodecError.invalidProfile }
            guard try protectionVersion(at: metadata) >= minimumJournalVersion,
                  try protectionVersion(at: config) >= minimumJournalVersion else { throw CodecError.protectionMissing }
            // A marker alone is insufficient if its underlying payload is unreadable.
            _ = try normalized(Data(contentsOf: metadata))
            _ = try normalized(Data(contentsOf: config))
        }
    }

    private static func protectionVersion(at url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let object = try dictionary(Data(contentsOf: url))
        guard let runtime = object["runtime"] as? [String: Any] else { return 0 }
        return try protectionVersion(runtime)
    }

    private static func protectionVersion(_ runtime: [String: Any]) throws -> Int {
        guard let kind = runtime["type"] as? String else { throw CodecError.invalidProfile }
        for version in protectionVersions where kind == "native_v\(version)" { return version }
        guard AgentRuntimeType(rawValue: kind) != nil else { throw CodecError.invalidProfile }
        return 0
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodecError.invalidProfile }
        return object
    }
}
