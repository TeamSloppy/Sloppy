import Foundation
import Logging
import PluginSDK
import Protocols

actor PersistentNodeGatewayRuntime {
    private struct NodeGatewayRequest: Encodable {
        var id: String
        var method: String
        var params: JSONValue
        var manifest: PluginManifest
    }

    private struct NodeGatewayMessage: Decodable {
        var id: String?
        var method: String?
        var params: JSONValue?
        var result: JSONValue?
        var error: NodeGatewayError?
    }

    private struct NodeGatewayResponse: Encodable {
        var id: String
        var result: JSONValue?
        var error: NodeGatewayError?
    }

    private struct NodeGatewayError: Codable, Error, Sendable {
        var code: String?
        var message: String
    }

    private final class ProcessOutputBuffer: @unchecked Sendable {
        var data = Data()
    }

    let manifest: PluginManifest

    private let entrypointURL: URL
    private let timeoutSeconds: TimeInterval
    private let logger: Logger
    private let inboundReceiver: any InboundMessageReceiver
    private let modelPickerBridge: (any TelegramModelPickerBridge)?
    private let toolApprovalBridge: (any ToolApprovalBridge)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        inboundReceiver: any InboundMessageReceiver,
        logger: Logger = Logger(label: "sloppy.plugin.node.gateway.persistent")
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
        self.inboundReceiver = inboundReceiver
        self.modelPickerBridge = inboundReceiver as? any TelegramModelPickerBridge
        self.toolApprovalBridge = inboundReceiver as? any ToolApprovalBridge
    }

    func startProcessIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

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

        let stderrBuffer = ProcessOutputBuffer()
        Task.detached {
            stderrBuffer.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        process.terminationHandler = { [weak self] process in
            let stderr = String(data: stderrBuffer.data, encoding: .utf8) ?? ""
            Task { await self?.handleTermination(status: process.terminationStatus, stderr: stderr) }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.handleStdout(data) }
        }

        try process.run()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        logger.info("Started persistent Node gateway process for \(manifest.name).")
    }

    func stopProcess() {
        if let process, process.isRunning {
            process.terminate()
        }
        stdinHandle = nil
        process = nil
        failPending(NodePluginRuntimeError.processFailed("Persistent Node gateway stopped."))
    }

    func callJSON(_ method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        try startProcessIfNeeded()
        let requestId = UUID().uuidString
        let request = NodeGatewayRequest(
            id: requestId,
            method: method,
            params: .object(params),
            manifest: manifest
        )
        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.registerPending(id: requestId, continuation: continuation)
                        do {
                            try await self.write(request)
                        } catch {
                            await self.resolvePending(id: requestId, result: .failure(error))
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(self.timeoutSeconds, 1) * 1_000_000_000))
                await self.resolvePending(id: requestId, result: .failure(NodePluginRuntimeError.timeout))
                throw NodePluginRuntimeError.timeout
            }
            guard let value = try await group.next() else {
                throw NodePluginRuntimeError.protocolError("missing response for \(method)")
            }
            group.cancelAll()
            return value
        }
    }

    private func registerPending(id: String, continuation: CheckedContinuation<JSONValue, Error>) {
        pending[id] = continuation
    }

    private func resolvePending(id: String, result: Result<JSONValue, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func failPending(_ error: Error) {
        let continuations = pending
        pending.removeAll()
        for (_, continuation) in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func write(_ request: NodeGatewayRequest) throws {
        let data = try JSONEncoder().encode(request)
        try writeLine(data)
    }

    private func writeResponse(id: String, result: JSONValue) {
        let response = NodeGatewayResponse(id: id, result: result, error: nil)
        if let data = try? JSONEncoder().encode(response) {
            try? writeLine(data)
        }
    }

    private func writeError(id: String, code: String, message: String) {
        let response = NodeGatewayResponse(id: id, result: nil, error: NodeGatewayError(code: code, message: message))
        if let data = try? JSONEncoder().encode(response) {
            try? writeLine(data)
        }
    }

    private func writeLine(_ data: Data) throws {
        guard let stdinHandle else {
            throw NodePluginRuntimeError.processFailed("Persistent Node gateway is not running.")
        }
        var line = data
        line.append(0x0A)
        try stdinHandle.write(contentsOf: line)
    }

    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(NodeGatewayMessage.self, from: data)
            if let method = message.method, let id = message.id {
                Task {
                    do {
                        let result = try await self.handleHostCall(method: method, params: message.params ?? .object([:]))
                        self.writeResponse(id: id, result: result)
                    } catch {
                        self.writeError(id: id, code: "host_error", message: String(describing: error))
                    }
                }
                return
            }

            guard let id = message.id else {
                logger.warning("Ignoring Node gateway message without id.")
                return
            }
            if let error = message.error {
                resolvePending(
                    id: id,
                    result: .failure(NodePluginRuntimeError.pluginError(code: error.code, message: error.message))
                )
            } else {
                resolvePending(id: id, result: .success(message.result ?? .null))
            }
        } catch {
            let text = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.warning("Invalid persistent Node gateway JSON line: \(text)")
        }
    }

    private func handleTermination(status: Int32, stderr: String) {
        logger.warning("Persistent Node gateway \(manifest.name) exited with status \(status). \(stderr)")
        process = nil
        stdinHandle = nil
        failPending(NodePluginRuntimeError.processFailed(stderr.isEmpty ? "Node gateway exited." : stderr))
    }

    private func handleHostCall(method: String, params: JSONValue) async throws -> JSONValue {
        let object = params.asObject ?? [:]
        switch method {
        case "host.inbound.postMessage", "inbound.postMessage":
            let ok = await inboundReceiver.postMessage(
                channelId: object["channelId"]?.asString ?? "",
                userId: object["userId"]?.asString ?? "",
                content: object["content"]?.asString ?? "",
                topicId: nullString(object["topicId"]),
                inboundContext: channelInboundContext(from: object["inboundContext"]?.asObject)
            )
            return .object(["ok": .bool(ok)])

        case "host.inbound.checkAccess", "inbound.checkAccess":
            let result = await inboundReceiver.checkAccess(
                platform: object["platform"]?.asString ?? "",
                platformUserId: object["platformUserId"]?.asString ?? "",
                displayName: object["displayName"]?.asString ?? "",
                chatId: object["chatId"]?.asString ?? ""
            )
            return encodeAccessResult(result)

        case "host.inbound.skillSlashCommandTokens", "inbound.skillSlashCommandTokens":
            let values = await inboundReceiver.skillSlashCommandTokens(forChannelID: object["channelId"]?.asString ?? "")
            return .array(values.map { .string($0) })

        case "host.inbound.skillSlashMenuEntriesUnion", "inbound.skillSlashMenuEntriesUnion":
            let ids = object["channelIds"]?.asArray?.compactMap(\.asString) ?? []
            return encodeJSONValue(await inboundReceiver.skillSlashMenuEntriesUnion(forChannelIDs: ids))

        case "host.inbound.projectLinkOptions", "inbound.projectLinkOptions":
            return .array((await inboundReceiver.projectLinkOptions()).map { option in
                .object([
                    "projectId": .string(option.projectId),
                    "name": .string(option.name)
                ])
            })

        case "host.inbound.projectLinkAgentOptions", "inbound.projectLinkAgentOptions":
            return .array((await inboundReceiver.projectLinkAgentOptions(projectId: object["projectId"]?.asString ?? "")).map { option in
                .object([
                    "actorId": .string(option.actorId),
                    "agentId": .string(option.agentId),
                    "name": .string(option.name),
                    "channelId": .string(option.channelId)
                ])
            })

        case "host.inbound.linkProjectChannel", "inbound.linkProjectChannel":
            let result = await inboundReceiver.linkProjectChannel(
                projectId: object["projectId"]?.asString ?? "",
                channelId: object["channelId"]?.asString ?? "",
                topicId: nullString(object["topicId"]),
                title: nullString(object["title"]),
                routeChannelId: nullString(object["routeChannelId"]),
                platform: nullString(object["platform"]),
                platformChannelId: nullString(object["platformChannelId"])
            )
            return encodeProjectLinkResult(result)

        case "host.inbound.answerChannelPlanInputOption", "inbound.answerChannelPlanInputOption":
            let ok = await inboundReceiver.answerChannelPlanInputOption(
                channelId: object["channelId"]?.asString ?? "",
                userId: object["userId"]?.asString ?? "",
                requestId: object["requestId"]?.asString ?? "",
                questionId: object["questionId"]?.asString ?? "",
                optionId: object["optionId"]?.asString ?? "",
                topicId: nullString(object["topicId"])
            )
            return .object(["ok": .bool(ok)])

        case "host.modelPicker.sortedModels", "modelPicker.sortedModels":
            return encodeJSONValue(await modelPickerBridge?.telegramPickerSortedModels() ?? [])

        case "host.modelPicker.currentModel", "modelPicker.currentModel":
            let current = await modelPickerBridge?.telegramPickerCurrentModelId(
                bindingChannelId: object["bindingChannelId"]?.asString ?? ""
            )
            return .object(["modelId": current.map(JSONValue.string) ?? .null])

        case "host.modelPicker.applyModel", "modelPicker.applyModel":
            guard let modelPickerBridge else {
                return .object(["ok": .bool(false), "message": .string("Model picker bridge unavailable.")])
            }
            let result = await modelPickerBridge.telegramPickerApplyModel(
                bindingChannelId: object["bindingChannelId"]?.asString ?? "",
                modelId: object["modelId"]?.asString ?? ""
            )
            switch result {
            case .success(let canonical):
                return .object(["ok": .bool(true), "modelId": .string(canonical)])
            case .failure(let error):
                return .object(["ok": .bool(false), "message": .string(error.message)])
            }

        case "host.toolApproval.resolve", "toolApproval.resolve":
            guard let toolApprovalBridge else {
                return .null
            }
            let record = await toolApprovalBridge.resolveToolApproval(
                id: object["id"]?.asString ?? "",
                approved: object["approved"]?.asBool ?? false,
                decidedBy: nullString(object["decidedBy"])
            )
            return record.map(encodeJSONValue) ?? .null

        default:
            throw NodePluginRuntimeError.protocolError("unsupported host method \(method)")
        }
    }

    private func channelInboundContext(from object: [String: JSONValue]?) -> ChannelInboundContext? {
        guard let object else { return nil }
        return ChannelInboundContext(
            mentionsThisBot: object["mentionsThisBot"]?.asBool ?? false,
            isReplyToThisBot: object["isReplyToThisBot"]?.asBool ?? false
        )
    }

    private func encodeAccessResult(_ result: ChannelAccessResult) -> JSONValue {
        switch result {
        case .allowed:
            return .object(["status": .string("allowed")])
        case .pendingApproval(let code, let message):
            return .object(["status": .string("pendingApproval"), "code": .string(code), "message": .string(message)])
        case .blocked:
            return .object(["status": .string("blocked")])
        }
    }

    private func encodeProjectLinkResult(_ result: ChannelProjectLinkResult) -> JSONValue {
        switch result {
        case .linked(let projectId, let projectName, let channelId, let status):
            return .object([
                "status": .string("linked"),
                "projectId": .string(projectId),
                "projectName": .string(projectName),
                "channelId": .string(channelId),
                "linkStatus": .string(status)
            ])
        case .conflict(let ownerProjectId, let ownerProjectName):
            return .object([
                "status": .string("conflict"),
                "ownerProjectId": .string(ownerProjectId),
                "ownerProjectName": .string(ownerProjectName)
            ])
        case .notFound:
            return .object(["status": .string("notFound")])
        case .failed(let message):
            return .object(["status": .string("failed"), "message": .string(message)])
        }
    }

    private func nullString(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        if case .null = value { return nil }
        let trimmed = value.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
