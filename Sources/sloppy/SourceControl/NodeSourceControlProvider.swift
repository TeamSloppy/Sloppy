import Foundation
import Logging
import Protocols
import PluginSDK

enum NodeSourceControlProviderError: Error, LocalizedError, Sendable {
    case protocolError(String)
    case pluginError(String)

    var errorDescription: String? {
        switch self {
        case .protocolError(let message):
            return "Node source-control plugin protocol error: \(message)"
        case .pluginError(let message):
            return message
        }
    }
}

struct NodeSourceControlProvider: SourceControlProvider {
    let id: String
    let displayName: String
    let capabilities: Set<SourceControlCapability>

    private let runtime: NodePluginRuntime
    private let manifest: PluginManifest

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        descriptor: NodePluginDescriptor? = nil,
        logger: Logger = Logger(label: "sloppy.source-control.node")
    ) throws {
        self.id = manifest.name
        let sourceControl = descriptor?.sourceControls.first
        self.displayName = sourceControl?.displayName ?? manifest.config["displayName"]?.asString ?? manifest.name
        self.capabilities = Self.capabilities(from: manifest.config, descriptor: sourceControl)
        self.runtime = try NodePluginRuntime(manifest: manifest, pluginDirectory: pluginDirectory, logger: logger)
        self.manifest = manifest
    }

    func inspectRepository(at path: String) async -> SourceControlRepositoryInfo {
        do {
            return try await call("inspectRepository", params: ["path": .string(path)], as: SourceControlRepositoryInfo.self)
        } catch {
            return SourceControlRepositoryInfo(
                providerId: id,
                isRepository: false,
                rootPath: path,
                message: error.localizedDescription
            )
        }
    }

    func workingTreeStatus(at path: String) async throws -> SourceControlWorkingTreeStatus {
        try await call("workingTreeStatus", params: ["path": .string(path)], as: SourceControlWorkingTreeStatus.self)
    }

    func workingTreeDiff(at path: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await call(
            "workingTreeDiff",
            params: ["path": .string(path), "maxBytes": .number(Double(maxBytes))],
            as: SourceControlDiffResult.self
        )
    }

    func branchDiff(at path: String, branchName: String, baseBranch: String, maxBytes: Int) async throws -> SourceControlDiffResult {
        try await call(
            "branchDiff",
            params: [
                "path": .string(path),
                "branchName": .string(branchName),
                "baseBranch": .string(baseBranch),
                "maxBytes": .number(Double(maxBytes)),
            ],
            as: SourceControlDiffResult.self
        )
    }

    func currentBranch(at path: String) async throws -> String? {
        let result = try await callJSON("currentBranch", params: ["path": .string(path)])
        if case .null = result {
            return nil
        }
        guard let value = result.asString else {
            throw NodeSourceControlProviderError.protocolError("currentBranch result must be a string or null.")
        }
        return value
    }

    func defaultBranch(at path: String) async throws -> String {
        try await call("defaultBranch", params: ["path": .string(path)], as: String.self)
    }

    func createWorktree(
        repoPath: String,
        taskId: String,
        baseBranch: String,
        worktreeRootPath: String?
    ) async throws -> SourceControlWorktreeResult {
        try await call(
            "createWorktree",
            params: [
                "repoPath": .string(repoPath),
                "taskId": .string(taskId),
                "baseBranch": .string(baseBranch),
                "worktreeRootPath": worktreeRootPath.map(JSONValue.string) ?? .null,
            ],
            as: SourceControlWorktreeResult.self
        )
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        _ = try await callJSON(
            "removeWorktree",
            params: ["repoPath": .string(repoPath), "worktreePath": .string(worktreePath)]
        )
    }

    func worktreePath(repoPath: String, taskId: String, worktreeRootPath: String?) -> String {
        let rootURL = worktreeRootPath
            .flatMap { path -> URL? in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
            }
            ?? URL(fileURLWithPath: repoPath)
                .appendingPathComponent(manifest.config["worktreeRootName"]?.asString ?? ".sloppy-worktrees", isDirectory: true)
        return rootURL
            .appendingPathComponent(taskId, isDirectory: true)
            .path
    }

    func restorePathFromHead(repoPath: String, relativePath: String) async throws {
        _ = try await callJSON(
            "restorePathFromHead",
            params: ["repoPath": .string(repoPath), "relativePath": .string(relativePath)]
        )
    }

    func mergeBranch(repoPath: String, branchName: String, targetBranch: String) async throws {
        _ = try await callJSON(
            "mergeBranch",
            params: [
                "repoPath": .string(repoPath),
                "branchName": .string(branchName),
                "targetBranch": .string(targetBranch),
            ]
        )
    }

    private func call<T: Decodable>(
        _ method: String,
        params: [String: JSONValue],
        as type: T.Type
    ) async throws -> T {
        let result = try await callJSON(method, params: params)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(type, from: data)
    }

    private func callJSON(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        do {
            return try await runtime.callJSON(runtimeMethod(for: method), params: params)
        } catch let error as NodePluginRuntimeError {
            if case .pluginError(let code, let message) = error {
                if code == "unsupported" {
                    throw SourceControlProviderError.unsupportedOperation(method)
                }
                throw NodeSourceControlProviderError.pluginError(message)
            }
            if case .protocolError(let message) = error {
                throw NodeSourceControlProviderError.protocolError(message)
            }
            throw error
        } catch {
            throw error
        }
    }

    private func runtimeMethod(for method: String) -> String {
        manifest.isNodePluginAPIV2 ? "source_control.\(method)" : method
    }

    private static func capabilities(
        from config: [String: JSONValue],
        descriptor: NodeSourceControlCapability?
    ) -> Set<SourceControlCapability> {
        let rawValues = descriptor?.capabilities ?? config["capabilities"]?.asArray?.compactMap(\.asString) ?? []
        return Set(rawValues.compactMap(SourceControlCapability.init(rawValue:)))
    }
}
