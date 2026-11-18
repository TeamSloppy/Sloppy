import Foundation
import AnyLanguageModel
import Protocols

struct ExecuteJavaScriptTool: CoreTool {
    let domain = "tools"
    let title = "Execute JavaScript"
    let status = "experimental"
    let name = CodeMode.toolID
    let description = """
        Run JavaScript to combine permitted tools. Use top-level await and return. Call tools by exact ID with tools.call("runtime.process", args), or use tools.runtime_process(args).
        Return only the fields or excerpts you need, such as error matches, exitCode, or a short outputTail. Keep full nested results in JS variables and check each result's ok field. Long output shows its beginning and end.
        To collect a background command's final result, call runtime.process with action "wait", the existing processId and an explicit timeoutMs. Set captureOutput: true when starting the command for a log tail. Use Promise.all to wait for several already-started commands.
        The first line can be // @options: {"max_output_tokens": 2000, "timeout_ms": 60000}. Raise timeout_ms to cover the expected wait. Discover calls with ALL_TOOLS, searchTools, describeTool and describeNamespace. Emit output with return, text or console.log. store/load keep small JSON values within this session.
        """
    private let storage = CodeModeStorage()

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "code", description: "JavaScript source, optionally starting with an @options line.", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        #if canImport(CSloppyQuickJS)
        guard CodeMode.enabled(workspaceRoot: context.workspaceRootURL), let invoke = context.invokeCodeModeTool else {
            return toolFailure(tool: name, code: "code_mode_unavailable", message: "Code Mode is unavailable in this execution context.", retryable: false)
        }
        guard let source = arguments["code"]?.asString, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Supply JavaScript in code.", retryable: false)
        }
        let options: CodeMode.Options
        do {
            options = try CodeMode.Options.parse(source)
        } catch {
            return toolFailure(tool: name, code: "invalid_arguments", message: error.localizedDescription, retryable: false)
        }

        let entries = await ToolCatalog.discoveryEntries(mcpRegistry: context.mcpRegistry, codeModeEnabled: true)
        let catalog = entries.filter {
            !CodeMode.excludedToolIDs.contains($0.id) &&
                ToolDiscoveryService.isVisible($0, policy: context.policy, allowedIDs: context.discoveryAllowedToolIDs)
        }
        let tools = catalog.map { entry in
            JSONValue.object([
                "name": .string(entry.id),
                "description": .string(String(entry.description.prefix(4_096))),
                "namespace": .string(entry.mcp?.serverID ?? entry.id.split(separator: ".").first.map(String.init) ?? ""),
                "parameters": entry.mcp?.inputSchema ?? ToolCatalog.codeModeSchema(for: entry.id)
            ])
        }
        let mcpTargets = Dictionary(catalog.compactMap { entry in entry.mcp.map { (entry.id, $0) } },
                                    uniquingKeysWith: { first, _ in first })
        let scope = CodeModeStorage.Scope(agentID: context.agentID, sessionID: context.sessionID)
        do {
            let result = try await CodeMode.run(source: source, options: options, catalog: tools, stored: storage.values(scope)) { request in
                if let target = mcpTargets[request.tool] {
                    return await invoke(.init(tool: "mcp.call_tool", arguments: [
                        "server": .string(target.serverID),
                        "tool": .string(target.toolName),
                        "arguments": .object(request.arguments)
                    ]))
                }
                return await invoke(request)
            }
            let state = result.snapshot
            var data = output(state, maxTokens: options.maxOutputTokens ?? 2_000)
            data["verificationEvidence"] = result.verificationEvidence
            if let error = state.error {
                return .init(tool: name, ok: false, data: .object(data),
                    error: .init(code: "javascript_error", message: error, retryable: false))
            }
            await storage.merge(state.writes ?? [:], scope: scope)
            return toolSuccess(tool: name, data: .object(data))
        } catch is CancellationError {
            return toolFailure(tool: name, code: "tool_cancelled", message: "JavaScript execution cancelled.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "javascript_error", message: error.localizedDescription, retryable: false)
        }
        #else
        return toolFailure(tool: name, code: "code_mode_unavailable", message: "Code Mode is unavailable on this platform.", retryable: false)
        #endif
    }

    private func output(_ state: CodeMode.Snapshot, maxTokens: Int) -> [String: JSONValue] {
        // The active model may not publish its tokenizer. Use a byte-based estimate.
        let budget = maxTokens * 4
        let text = state.output?.preview(maxBytes: budget) ?? (text: "", truncated: false)
        let logs = state.logs?.preview(maxBytes: budget - text.text.utf8.count) ?? (text: "", truncated: false)
        return [
            "output": .string(text.text),
            "console": .string(logs.text),
            "truncated": .bool(text.truncated || logs.truncated)
        ]
    }
}

private actor CodeModeStorage {
    struct Scope: Hashable, Sendable {
        let agentID: String
        let sessionID: String
    }

    private var sessions: [Scope: [String: JSONValue]] = [:]
    private var order: [Scope] = []

    func values(_ scope: Scope) -> [String: JSONValue] { sessions[scope] ?? [:] }

    func merge(_ changes: [String: JSONValue], scope: Scope) {
        guard !changes.isEmpty else { return }
        var values = sessions[scope] ?? [:]
        for (key, value) in changes where key.utf8.count <= 512 {
            if values[key] != nil || values.count < 32 {
                values[key] = value
            }
        }
        guard let data = try? JSONEncoder().encode(values), data.count <= 32 * 1024 else { return }
        order.removeAll { $0 == scope }
        order.append(scope)
        sessions[scope] = values
        if order.count > 128 { sessions.removeValue(forKey: order.removeFirst()) }
    }
}
