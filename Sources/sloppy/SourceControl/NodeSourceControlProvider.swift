import Foundation
import Logging
import Protocols
import PluginSDK

enum NodeSourceControlProviderError: Error, LocalizedError, Sendable {
    case missingEntrypoint
    case invalidEntrypoint(String)
    case processFailed(String)
    case timeout
    case protocolError(String)
    case pluginError(String)

    var errorDescription: String? {
        switch self {
        case .missingEntrypoint:
            return "Node source-control plugin is missing an entrypoint."
        case .invalidEntrypoint(let path):
            return "Node source-control plugin entrypoint is invalid: \(path)"
        case .processFailed(let message):
            return message
        case .timeout:
            return "Node source-control plugin timed out."
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

    private let entrypointURL: URL
    private let manifest: PluginManifest
    private let timeoutSeconds: TimeInterval
    private let logger: Logger

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger(label: "sloppy.source-control.node")
    ) throws {
        guard let entrypoint = manifest.entrypoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entrypoint.isEmpty
        else {
            throw NodeSourceControlProviderError.missingEntrypoint
        }

        let entrypointURL = pluginDirectory.appendingPathComponent(entrypoint).standardizedFileURL
        let pluginRoot = pluginDirectory.standardizedFileURL.path
        guard entrypointURL.path == pluginRoot || entrypointURL.path.hasPrefix(pluginRoot + "/") else {
            throw NodeSourceControlProviderError.invalidEntrypoint(entrypoint)
        }
        guard FileManager.default.fileExists(atPath: entrypointURL.path) else {
            throw NodeSourceControlProviderError.invalidEntrypoint(entrypoint)
        }

        self.id = manifest.name
        self.displayName = manifest.config["displayName"]?.asString ?? manifest.name
        self.capabilities = Self.capabilities(from: manifest.config)
        self.entrypointURL = entrypointURL
        self.manifest = manifest
        self.timeoutSeconds = TimeInterval(manifest.config["timeoutMs"]?.asInt ?? 30_000) / 1000
        self.logger = logger
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

    func createWorktree(repoPath: String, taskId: String, baseBranch: String) async throws -> SourceControlWorktreeResult {
        try await call(
            "createWorktree",
            params: [
                "repoPath": .string(repoPath),
                "taskId": .string(taskId),
                "baseBranch": .string(baseBranch),
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

    func worktreePath(repoPath: String, taskId: String) -> String {
        URL(fileURLWithPath: repoPath)
            .appendingPathComponent(manifest.config["worktreeRootName"]?.asString ?? ".sloppy-worktrees", isDirectory: true)
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
        let request = NodePluginRequest(
            id: UUID().uuidString,
            method: method,
            params: .object(params),
            manifest: manifest
        )
        let data = try JSONEncoder().encode(request)
        let line = String(decoding: data, as: UTF8.self) + "\n"
        let output = try await runNode(input: line)
        guard let responseLine = output.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first
        else {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NodeSourceControlProviderError.protocolError(message.isEmpty ? "empty stdout" : message)
        }

        let response = try JSONDecoder().decode(NodePluginResponse.self, from: Data(responseLine.utf8))
        if let error = response.error {
            if error.code == "unsupported" {
                throw SourceControlProviderError.unsupportedOperation(method)
            }
            throw NodeSourceControlProviderError.pluginError(error.message)
        }
        guard let result = response.result else {
            throw NodeSourceControlProviderError.protocolError("missing result for \(method)")
        }
        return result
    }

    private func runNode(input: String) async throws -> (stdout: String, stderr: String) {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", entrypointURL.path]
            process.currentDirectoryURL = entrypointURL.deletingLastPathComponent()
            process.environment = childProcessEnvironment()

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = NodePluginOutputBuffer()
            let stderrBuffer = NodePluginOutputBuffer()

            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
            try? stdinPipe.fileHandleForWriting.close()

            let stdoutTask = Task.detached {
                stdoutBuffer.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let stderrTask = Task.detached {
                stderrBuffer.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if process.isRunning {
                process.terminate()
                throw NodeSourceControlProviderError.timeout
            }

            await stdoutTask.value
            await stderrTask.value

            let stdout = String(data: stdoutBuffer.data, encoding: .utf8) ?? ""
            let stderr = String(data: stderrBuffer.data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let message = [stdout, stderr]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                throw NodeSourceControlProviderError.processFailed(message)
            }
            return (stdout, stderr)
        }.value
    }

    private static func capabilities(from config: [String: JSONValue]) -> Set<SourceControlCapability> {
        let rawValues = config["capabilities"]?.asArray?.compactMap(\.asString) ?? []
        return Set(rawValues.compactMap(SourceControlCapability.init(rawValue:)))
    }
}

private struct NodePluginRequest: Encodable {
    var id: String
    var method: String
    var params: JSONValue
    var manifest: PluginManifest
}

private struct NodePluginResponse: Decodable {
    var id: String?
    var result: JSONValue?
    var error: NodePluginError?
}

private struct NodePluginError: Decodable {
    var code: String?
    var message: String
}

private final class NodePluginOutputBuffer: @unchecked Sendable {
    var data = Data()
}
