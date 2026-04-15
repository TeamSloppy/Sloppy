import AnyLanguageModel
import Foundation
import Protocols

struct MCPSaveServerTool: CoreTool {
    let domain = "mcp"
    let title = "Save MCP server"
    let status = "fully_functional"
    let name = "mcp.save_server"
    let description = "Add or update an MCP server entry in runtime config."

    var toolAliases: [String] { ["mcp.update_server"] }

    var parameters: GenerationSchema {
        mcpServerSchema(includeInstallCommand: false, includeUninstallCommand: false)
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let configService = context.configService else {
            return toolFailure(tool: name, code: "not_available", message: "Runtime config service is unavailable.", retryable: true)
        }

        do {
            let server = try parseServer(arguments: arguments)
            var config = await configService.runtimeConfig()
            if let index = config.mcp.servers.firstIndex(where: { $0.id == server.id }) {
                config.mcp.servers[index] = server
            } else {
                config.mcp.servers.append(server)
            }
            let updated = try await configService.updateRuntimeConfig(config)
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": encodeJSONValue(server),
                    "serverCount": .number(Double(updated.mcp.servers.count))
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_config_error", message: String(describing: error), retryable: false)
        }
    }
}

struct MCPRemoveServerTool: CoreTool {
    let domain = "mcp"
    let title = "Remove MCP server"
    let status = "fully_functional"
    let name = "mcp.remove_server"
    let description = "Remove an MCP server entry from runtime config."

    var toolAliases: [String] { ["mcp.delete_server"] }

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self))
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let configService = context.configService else {
            return toolFailure(tool: name, code: "not_available", message: "Runtime config service is unavailable.", retryable: true)
        }
        guard let serverID = trimmedArg("server", from: arguments) else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }

        var config = await configService.runtimeConfig()
        let initialCount = config.mcp.servers.count
        config.mcp.servers.removeAll { $0.id == serverID }
        guard config.mcp.servers.count != initialCount else {
            return toolFailure(tool: name, code: "not_found", message: "MCP server '\(serverID)' is not configured.", retryable: false)
        }

        do {
            let updated = try await configService.updateRuntimeConfig(config)
            return toolSuccess(
                tool: name,
                data: .object([
                    "server": .string(serverID),
                    "serverCount": .number(Double(updated.mcp.servers.count))
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_config_error", message: String(describing: error), retryable: false)
        }
    }
}

struct MCPInstallServerTool: CoreTool {
    let domain = "mcp"
    let title = "Install MCP server"
    let status = "fully_functional"
    let name = "mcp.install_server"
    let description = "Run an install command for an MCP server and save it into runtime config."

    var parameters: GenerationSchema {
        mcpServerSchema(includeInstallCommand: true, includeUninstallCommand: false)
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let configService = context.configService else {
            return toolFailure(tool: name, code: "not_available", message: "Runtime config service is unavailable.", retryable: true)
        }

        do {
            let installResult = try await runManagedCommand(
                commandKey: "installCommand",
                argumentsKey: "installArguments",
                cwdKey: "installCwd",
                arguments: arguments,
                context: context
            )
            let installPayload = installResult.asObject ?? [:]

            guard installPayload["exitCode"]?.asInt == 0,
                  installPayload["timedOut"]?.asBool != true else {
                return toolFailure(tool: name, code: "install_failed", message: "Install command failed.", retryable: true)
            }

            let server = try parseServer(arguments: arguments)
            var config = await configService.runtimeConfig()
            if let index = config.mcp.servers.firstIndex(where: { $0.id == server.id }) {
                config.mcp.servers[index] = server
            } else {
                config.mcp.servers.append(server)
            }
            let updated = try await configService.updateRuntimeConfig(config)
            return toolSuccess(
                tool: name,
                data: .object([
                    "install": installResult,
                    "server": encodeJSONValue(server),
                    "serverCount": .number(Double(updated.mcp.servers.count))
                ])
            )
        } catch {
            return toolFailure(tool: name, code: "mcp_install_error", message: String(describing: error), retryable: false)
        }
    }
}

struct MCPUninstallServerTool: CoreTool {
    let domain = "mcp"
    let title = "Uninstall MCP server"
    let status = "fully_functional"
    let name = "mcp.uninstall_server"
    let description = "Run an uninstall command for an MCP server and optionally remove it from runtime config."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "server", description: "Configured MCP server id", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "removeFromConfig", description: "Whether to remove the server entry after uninstall", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
            .init(name: "uninstallCommand", description: "Install/uninstall command to execute", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "uninstallArguments", description: "Install/uninstall command arguments", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "uninstallCwd", description: "Working directory for uninstall command", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let configService = context.configService else {
            return toolFailure(tool: name, code: "not_available", message: "Runtime config service is unavailable.", retryable: true)
        }
        guard let serverID = trimmedArg("server", from: arguments) else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Argument 'server' is required.", retryable: false)
        }

        var uninstallResult: JSONValue = .null
        if trimmedArg("uninstallCommand", from: arguments) != nil {
            do {
                uninstallResult = try await runManagedCommand(
                    commandKey: "uninstallCommand",
                    argumentsKey: "uninstallArguments",
                    cwdKey: "uninstallCwd",
                    arguments: arguments,
                    context: context
                )
                let uninstallPayload = uninstallResult.asObject ?? [:]
                guard uninstallPayload["exitCode"]?.asInt == 0,
                      uninstallPayload["timedOut"]?.asBool != true else {
                    return toolFailure(tool: name, code: "uninstall_failed", message: "Uninstall command failed.", retryable: true)
                }
            } catch {
                return toolFailure(tool: name, code: "uninstall_failed", message: String(describing: error), retryable: true)
            }
        }

        let removeFromConfig = arguments["removeFromConfig"]?.asBool ?? true
        if removeFromConfig {
            var config = await configService.runtimeConfig()
            config.mcp.servers.removeAll { $0.id == serverID }
            do {
                let updated = try await configService.updateRuntimeConfig(config)
                return toolSuccess(
                    tool: name,
                    data: .object([
                        "server": .string(serverID),
                        "uninstall": uninstallResult,
                        "serverCount": .number(Double(updated.mcp.servers.count))
                    ])
                )
            } catch {
                return toolFailure(tool: name, code: "mcp_config_error", message: String(describing: error), retryable: false)
            }
        }

        return toolSuccess(
            tool: name,
            data: .object([
                "server": .string(serverID),
                "uninstall": uninstallResult,
                "removedFromConfig": .bool(false)
            ])
        )
    }
}

private func mcpServerSchema(includeInstallCommand: Bool, includeUninstallCommand: Bool) -> GenerationSchema {
    var properties: [DynamicGenerationSchema.Property] = [
        .init(name: "id", description: "MCP server id", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "transport", description: "Transport: stdio or http", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "command", description: "Command for stdio transport", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "arguments", description: "Arguments for stdio transport", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
        .init(name: "cwd", description: "Working directory for stdio transport", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "endpoint", description: "HTTP endpoint for http transport", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "timeoutMs", description: "Timeout in milliseconds", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        .init(name: "enabled", description: "Whether the server is enabled", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        .init(name: "exposeTools", description: "Expose dynamic MCP tools", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        .init(name: "exposeResources", description: "Expose resources", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        .init(name: "exposePrompts", description: "Expose prompts", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        .init(name: "toolPrefix", description: "Optional dynamic tool prefix", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(
            name: "headers",
            description: "HTTP headers object",
            schema: DynamicGenerationSchema(
                name: "Headers",
                properties: [
                    .init(name: "Authorization", description: "Example header value", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
                ]
            ),
            isOptional: true
        )
    ]

    if includeInstallCommand {
        properties.append(contentsOf: [
            .init(name: "installCommand", description: "Install command to execute before saving config", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "installArguments", description: "Install command arguments", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "installCwd", description: "Working directory for install command", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    if includeUninstallCommand {
        properties.append(contentsOf: [
            .init(name: "uninstallCommand", description: "Uninstall command", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    return .objectSchema(properties)
}

private func parseServer(arguments: [String: JSONValue]) throws -> CoreConfig.MCP.Server {
    guard let id = trimmedArg("id", from: arguments) else {
        throw MCPRegistryError.invalidConfiguration("Argument 'id' is required.")
    }
    let rawTransport = trimmedArg("transport", from: arguments) ?? "stdio"
    guard let transport = CoreConfig.MCP.Server.Transport(rawValue: rawTransport) else {
        throw MCPRegistryError.invalidConfiguration("Unsupported MCP transport '\(rawTransport)'.")
    }

    let headerValues = arguments["headers"]?.asObject?.compactMapValues(\.asString) ?? [:]

    return CoreConfig.MCP.Server(
        id: id,
        transport: transport,
        command: trimmedArg("command", from: arguments),
        arguments: arguments["arguments"]?.asArray?.compactMap(\.asString) ?? [],
        cwd: trimmedArg("cwd", from: arguments),
        endpoint: trimmedArg("endpoint", from: arguments),
        headers: headerValues,
        timeoutMs: max(250, arguments["timeoutMs"]?.asInt ?? 15_000),
        enabled: arguments["enabled"]?.asBool ?? true,
        exposeTools: arguments["exposeTools"]?.asBool ?? false,
        exposeResources: arguments["exposeResources"]?.asBool ?? false,
        exposePrompts: arguments["exposePrompts"]?.asBool ?? false,
        toolPrefix: trimmedArg("toolPrefix", from: arguments)
    )
}

private func runManagedCommand(
    commandKey: String,
    argumentsKey: String,
    cwdKey: String,
    arguments: [String: JSONValue],
    context: ToolContext
) async throws -> JSONValue {
    guard let command = trimmedArg(commandKey, from: arguments) else {
        throw MCPRegistryError.invalidConfiguration("Argument '\(commandKey)' is required.")
    }
    guard isCommandAllowed(command, deniedPrefixes: context.policy.guardrails.deniedCommandPrefixes) else {
        throw MCPRegistryError.invalidConfiguration("Command '\(command)' is blocked by guardrails.")
    }

    let commandArguments = arguments[argumentsKey]?.asArray?.compactMap(\.asString) ?? []
    let cwdValue = trimmedArg(cwdKey, from: arguments)
    let cwdURL: URL?
    if let cwdValue {
        guard let resolved = context.resolveExecCwd(cwdValue) else {
            throw MCPRegistryError.invalidConfiguration("Install/uninstall CWD is outside allowed execution roots.")
        }
        cwdURL = resolved
    } else {
        cwdURL = context.currentDirectoryURL
    }

    return try await runForegroundProcess(
        command: command,
        arguments: commandArguments,
        cwd: cwdURL,
        timeoutMs: context.policy.guardrails.execTimeoutMs,
        maxOutputBytes: context.policy.guardrails.maxExecOutputBytes
    )
}
