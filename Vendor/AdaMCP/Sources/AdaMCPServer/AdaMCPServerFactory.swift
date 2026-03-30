import AdaMCPCore
import MCP

public enum AdaMCPServerFactory {
    public static func makeServer(
        runtime: AdaMCPRuntime,
        configuration: MCPServerConfiguration
    ) async -> Server {
        let server = Server(
            name: configuration.serverName,
            version: configuration.serverVersion,
            instructions: configuration.instructions,
            capabilities: .init(
                resources: .init(listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: await runtime.tools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            await runtime.callTool(name: params.name, arguments: params.arguments ?? [:])
        }

        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: await runtime.resources())
        }

        await server.withMethodHandler(ReadResource.self) { params in
            try await runtime.readResource(uri: params.uri)
        }

        return server
    }
}

public actor AdaMCPHTTPServerController {
    private let configuration: EmbeddedHTTPMCPServer.Configuration
    private let runtime: AdaMCPRuntime
    private let logger = Logger(label: "org.adaengine.mcp.server")
    private var app: EmbeddedHTTPMCPServer?

    public init(configuration: MCPServerConfiguration, runtime: AdaMCPRuntime) {
        self.configuration = .init(
            host: configuration.host,
            port: configuration.port,
            endpoint: configuration.endpoint
        )
        self.runtime = runtime
    }

    public func start(configuration: MCPServerConfiguration) async throws -> URL {
        if let app {
            return try await app.start()
        }

        let app = EmbeddedHTTPMCPServer(
            configuration: configurationForApp(configuration),
            serverFactory: { _ in
                await AdaMCPServerFactory.makeServer(runtime: self.runtime, configuration: configuration)
            },
            logger: logger
        )
        self.app = app
        return try await app.start()
    }

    public func stop() async {
        await app?.stop()
        app = nil
    }

    private func configurationForApp(_ configuration: MCPServerConfiguration) -> EmbeddedHTTPMCPServer.Configuration {
        .init(
            host: configuration.host,
            port: configuration.port,
            endpoint: configuration.endpoint
        )
    }
}
