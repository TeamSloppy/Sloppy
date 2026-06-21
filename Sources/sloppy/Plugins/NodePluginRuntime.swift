import Foundation
import Logging
import Protocols

enum NodePluginRuntimeError: Error, LocalizedError, Sendable {
    case missingEntrypoint
    case invalidEntrypoint(String)
    case processFailed(String)
    case timeout
    case protocolError(String)
    case pluginError(code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .missingEntrypoint:
            return "Node plugin is missing an entrypoint."
        case .invalidEntrypoint(let path):
            return "Node plugin entrypoint is invalid: \(path)"
        case .processFailed(let message):
            return message
        case .timeout:
            return "Node plugin timed out."
        case .protocolError(let message):
            return "Node plugin protocol error: \(message)"
        case .pluginError(_, let message):
            return message
        }
    }
}

struct NodePluginRuntime: Sendable {
    let manifest: PluginManifest

    private let entrypointURL: URL
    private let timeoutSeconds: TimeInterval
    private let logger: Logger

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        logger: Logger = Logger.sloppy(label: "sloppy.plugin.node")
    ) throws {
        guard let entrypoint = manifest.entrypoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !entrypoint.isEmpty
        else {
            throw NodePluginRuntimeError.missingEntrypoint
        }

        let entrypointURL = pluginDirectory.appendingPathComponent(entrypoint).standardizedFileURL
        let pluginRoot = pluginDirectory.standardizedFileURL.path
        guard entrypointURL.path == pluginRoot || entrypointURL.path.hasPrefix(pluginRoot + "/") else {
            throw NodePluginRuntimeError.invalidEntrypoint(entrypoint)
        }
        guard FileManager.default.fileExists(atPath: entrypointURL.path) else {
            throw NodePluginRuntimeError.invalidEntrypoint(entrypoint)
        }

        self.manifest = manifest
        self.entrypointURL = entrypointURL
        self.timeoutSeconds = TimeInterval(manifest.config["timeoutMs"]?.asInt ?? 30_000) / 1000
        self.logger = logger
    }

    func call<T: Decodable>(
        _ method: String,
        params: [String: JSONValue] = [:],
        as type: T.Type
    ) async throws -> T {
        let result = try await callJSON(method, params: params)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(type, from: data)
    }

    func callJSON(_ method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
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
            throw NodePluginRuntimeError.protocolError(message.isEmpty ? "empty stdout" : message)
        }

        let response = try JSONDecoder().decode(NodePluginResponse.self, from: Data(responseLine.utf8))
        if let error = response.error {
            throw NodePluginRuntimeError.pluginError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw NodePluginRuntimeError.protocolError("missing result for \(method)")
        }
        return result
    }

    func describe() async throws -> NodePluginDescriptor {
        try await call(
            "plugin.describe",
            params: ["manifest": encodeJSONValue(manifest)],
            as: NodePluginDescriptor.self
        )
    }

    private func runNode(input: String) async throws -> (stdout: String, stderr: String) {
        let entrypointURL = entrypointURL
        let timeoutSeconds = timeoutSeconds
        return try await Task.detached(priority: .utility) {
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
                throw NodePluginRuntimeError.timeout
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
                throw NodePluginRuntimeError.processFailed(message)
            }
            return (stdout, stderr)
        }.value
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

struct NodePluginDescriptor: Decodable, Sendable, Equatable {
    var tools: [NodeToolCapability]
    var hooks: [NodeNamedCapability]
    var commands: [NodeNamedCapability]
    var skills: [NodeNamedCapability]
    var gateways: [NodeGatewayCapability]
    var sourceControls: [NodeSourceControlCapability]
    var memories: [NodeNamedCapability]
    var modelProviders: [NodeNamedCapability]

    private enum CodingKeys: String, CodingKey {
        case tools
        case hooks
        case commands
        case skills
        case gateways
        case sourceControls
        case sourceControl = "source_control"
        case memories
        case memory
        case modelProviders
        case providers
    }

    init(
        tools: [NodeToolCapability] = [],
        hooks: [NodeNamedCapability] = [],
        commands: [NodeNamedCapability] = [],
        skills: [NodeNamedCapability] = [],
        gateways: [NodeGatewayCapability] = [],
        sourceControls: [NodeSourceControlCapability] = [],
        memories: [NodeNamedCapability] = [],
        modelProviders: [NodeNamedCapability] = []
    ) {
        self.tools = tools
        self.hooks = hooks
        self.commands = commands
        self.skills = skills
        self.gateways = gateways
        self.sourceControls = sourceControls
        self.memories = memories
        self.modelProviders = modelProviders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tools = try container.decodeIfPresent([NodeToolCapability].self, forKey: .tools) ?? []
        hooks = try container.decodeIfPresent([NodeNamedCapability].self, forKey: .hooks) ?? []
        commands = try container.decodeIfPresent([NodeNamedCapability].self, forKey: .commands) ?? []
        skills = try container.decodeIfPresent([NodeNamedCapability].self, forKey: .skills) ?? []
        gateways = try container.decodeIfPresent([NodeGatewayCapability].self, forKey: .gateways) ?? []
        let sourceControls = try container.decodeIfPresent([NodeSourceControlCapability].self, forKey: .sourceControls)
        let sourceControl = try container.decodeIfPresent([NodeSourceControlCapability].self, forKey: .sourceControl)
        self.sourceControls = sourceControls ?? sourceControl ?? []
        memories = try container.decodeIfPresent([NodeNamedCapability].self, forKey: .memories)
            ?? container.decodeIfPresent([NodeNamedCapability].self, forKey: .memory)
            ?? []
        modelProviders = try container.decodeIfPresent([NodeNamedCapability].self, forKey: .modelProviders)
            ?? container.decodeIfPresent([NodeNamedCapability].self, forKey: .providers)
            ?? []
    }
}

struct NodeNamedCapability: Codable, Sendable, Equatable {
    var name: String
    var title: String?
    var description: String?
}

struct NodeGatewayCapability: Codable, Sendable, Equatable {
    var name: String
    var title: String?
    var description: String?
    var channelIds: [String]
    var capabilities: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case channelIds
        case capabilities
    }

    init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        channelIds: [String] = [],
        capabilities: [String] = []
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.channelIds = channelIds
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        channelIds = try container.decodeIfPresent([String].self, forKey: .channelIds) ?? []
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}

struct NodeToolCapability: Codable, Sendable, Equatable {
    var name: String
    var title: String?
    var description: String?
    var schema: JSONValue?
    var inputSchema: JSONValue?
    var status: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case schema
        case inputSchema
        case status
    }

    var effectiveSchema: JSONValue {
        inputSchema ?? schema ?? .object(["type": .string("object")])
    }
}

struct NodeSourceControlCapability: Codable, Sendable, Equatable {
    var name: String?
    var displayName: String?
    var capabilities: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case capabilities
    }

    init(name: String? = nil, displayName: String? = nil, capabilities: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}
