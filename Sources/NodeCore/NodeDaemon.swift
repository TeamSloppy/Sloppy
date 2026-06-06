import Foundation
import Protocols
import SloppyComputerControl

#if canImport(Security)
import Security
#endif

public struct NodeIdentity: Codable, Sendable, Equatable {
    public var nodeId: String
    public var name: String
    public var publicKey: String
    public var privateKey: String
    public var roles: [String]
    public var capabilities: [String]
    public var createdAt: Date

    public init(
        nodeId: String,
        name: String,
        publicKey: String,
        privateKey: String,
        roles: [String],
        capabilities: [String],
        createdAt: Date = Date()
    ) {
        self.nodeId = nodeId
        self.name = name
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.roles = roles
        self.capabilities = capabilities
        self.createdAt = createdAt
    }
}

public struct NodeConfig: Codable, Sendable, Equatable {
    public var identity: NodeIdentity
    public var relayURL: String?

    public init(identity: NodeIdentity, relayURL: String? = nil) {
        self.identity = identity
        self.relayURL = relayURL
    }
}

public enum NodeConfigError: LocalizedError, Equatable {
    case alreadyExists(String)
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let path):
            "Node config already exists at \(path). Use --force to replace it."
        case .missing(let path):
            "Node config does not exist at \(path). Run `sloppy-node init` first."
        }
    }
}

public struct NodeConfigStore: Sendable {
    public var configURL: URL

    public init(configURL: URL = NodeConfigStore.defaultConfigURL()) {
        self.configURL = configURL
    }

    public static func defaultConfigURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".sloppy/node.json")
    }

    public func load() throws -> NodeConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw NodeConfigError.missing(configURL.path)
        }
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NodeConfig.self, from: data)
    }

    @discardableResult
    public func initialize(
        name: String,
        roles: [String],
        capabilities: [String],
        relayURL: String? = nil,
        force: Bool = false
    ) throws -> NodeConfig {
        if FileManager.default.fileExists(atPath: configURL.path), !force {
            throw NodeConfigError.alreadyExists(configURL.path)
        }

        let config = NodeConfig(
            identity: NodeIdentity(
                nodeId: NodeIdentityGenerator.makeNodeId(name: name),
                name: name,
                publicKey: "ed25519:" + NodeIdentityGenerator.randomToken(byteCount: 32),
                privateKey: "ed25519:" + NodeIdentityGenerator.randomToken(byteCount: 64),
                roles: roles,
                capabilities: capabilities
            ),
            relayURL: relayURL
        )
        try save(config)
        return config
    }

    public func save(_ config: NodeConfig) throws {
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
        try restrictOwnerAccess(at: configURL)
    }

    private func restrictOwnerAccess(at url: URL) throws {
        #if os(Windows)
        return
        #else
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}

public enum NodeIdentityGenerator {
    public static func makeNodeId(name: String) -> String {
        let slug = name
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-")
            .joined(separator: "-")
        let prefix = slug.isEmpty ? "node" : slug
        return "node_\(prefix)_\(randomToken(byteCount: 6))"
    }

    public static func randomToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if fillRandomBytes(&bytes) == false {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
            }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fillRandomBytes(_ bytes: inout [UInt8]) -> Bool {
        #if canImport(Darwin)
        return SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
        #else
        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            return false
        }
        defer { try? handle.close() }
        do {
            let data = try handle.read(upToCount: bytes.count) ?? Data()
            guard data.count == bytes.count else { return false }
            bytes = Array(data)
            return true
        } catch {
            return false
        }
        #endif
    }
}

public struct ProcessResult: Codable, Sendable, Equatable {
    public var command: String
    public var arguments: [String]
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(command: String, arguments: [String], exitCode: Int32, stdout: String, stderr: String) {
        self.command = command
        self.arguments = arguments
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public actor NodeDaemon {
    public enum State: String, Sendable {
        case idle
        case connected
        case runningTask
    }

    public let nodeId: String
    public private(set) var state: State = .idle
    public private(set) var lastHeartbeatAt: Date?

    private let computerController: any ComputerControlling

    public init(nodeId: String = UUID().uuidString, computerController: any ComputerControlling = PlatformComputerController()) {
        self.nodeId = nodeId
        self.computerController = computerController
    }

    public init(config: NodeConfig, computerController: any ComputerControlling = PlatformComputerController()) {
        self.nodeId = config.identity.nodeId
        self.computerController = computerController
    }

    public func connect() {
        state = .connected
        lastHeartbeatAt = Date()
    }

    public func heartbeat() {
        lastHeartbeatAt = Date()
    }

    public func invoke(_ request: NodeActionRequest) async -> NodeActionResponse {
        do {
            switch request.action {
            case .exec:
                let payload = try JSONValueCoder.decode(NodeExecPayload.self, from: request.payload)
                let result = try await spawnProcess(command: payload.command, arguments: payload.arguments)
                return .success(action: request.action, data: try JSONValueCoder.encode(result))
            case .computerClick:
                let payload = try JSONValueCoder.decode(ComputerClickPayload.self, from: request.payload)
                try validateClickPayload(payload)
                let data = try await computerController.click(payload)
                return .success(action: request.action, data: JSONValue(computerControlValue: data))
            case .computerTypeText:
                let payload = try JSONValueCoder.decode(ComputerTypeTextPayload.self, from: request.payload)
                let data = try await computerController.typeText(payload)
                return .success(action: request.action, data: JSONValue(computerControlValue: data))
            case .computerKey:
                let payload = try JSONValueCoder.decode(ComputerKeyPayload.self, from: request.payload)
                let data = try await computerController.key(payload)
                return .success(action: request.action, data: JSONValue(computerControlValue: data))
            case .computerScreenshot:
                let payload = try JSONValueCoder.decode(ComputerScreenshotPayload.self, from: request.payload)
                let result = try await computerController.screenshot(payload)
                return .success(action: request.action, data: try JSONValueCoder.encode(result))
            case .status:
                return .success(action: request.action, data: .object([
                    "nodeId": .string(nodeId),
                    "state": .string(state.rawValue),
                    "platform": .string(computerControlPlatformName)
                ]))
            }
        } catch let error as ComputerControlError {
            return .failure(action: request.action, code: error.code, message: error.localizedDescription)
        } catch {
            return .failure(action: request.action, code: "invalid_request", message: error.localizedDescription)
        }
    }

    public func spawnProcess(command: String, arguments: [String]) async throws -> ProcessResult {
        state = .runningTask
        defer { state = .connected }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            command: command,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    public func readText(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public func writeText(_ content: String, to path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let directory = fileURL.deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

private extension JSONValue {
    init(computerControlValue value: ComputerControlValue) {
        switch value {
        case .null:
            self = .null
        case .bool(let value):
            self = .bool(value)
        case .number(let value):
            self = .number(value)
        case .string(let value):
            self = .string(value)
        case .array(let value):
            self = .array(value.map(JSONValue.init(computerControlValue:)))
        case .object(let value):
            self = .object(value.mapValues(JSONValue.init(computerControlValue:)))
        }
    }
}
