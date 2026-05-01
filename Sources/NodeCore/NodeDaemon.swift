import Foundation
import Protocols
import SloppyComputerControl

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
