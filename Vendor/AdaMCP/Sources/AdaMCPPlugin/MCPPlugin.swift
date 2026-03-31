import AdaEngine
import AdaMCPCore
import AdaMCPServer
import Logging

@MainActor
public struct MCPPlugin: Plugin {
    @MainActor
    final class State: @unchecked Sendable {
        let registry = MCPIntrospectionRegistry()
        let runtimeResource = MCPServerRuntime()
        let logger = Logger(label: "org.adaengine.mcp.plugin")
        var httpController: AdaMCPHTTPServerController?
        var stdioController: AdaMCPStdioServerController?
        var renderCaptureService: RenderCaptureService?
    }

    private let configuration: MCPServerConfiguration
    private let state: State

    public init(configuration: MCPServerConfiguration = .init()) {
        self.configuration = configuration
        self.state = State()
    }

    public func setup(in app: borrowing AppWorlds) {
        AdaMCPBuiltins.registerDefaultTypes(in: state.registry)
        configuration.registerTypes?(state.registry)

        let appWorlds = copy app
        let renderCaptureService = RenderCaptureService(
            appWorlds: appWorlds,
            captureOverride: configuration.captureOverride
        )
        state.renderCaptureService = renderCaptureService

        app.insertResource(state.runtimeResource)
        app.insertResource(renderCaptureService)
    }

    public func finish(for app: borrowing AppWorlds) {
        AdaMCPBuiltins.registerAssetDescriptors(in: state.registry)
        guard let renderCaptureService = state.renderCaptureService else {
            return
        }

        let appWorlds = copy app
        let runtime = AdaMCPRuntime(
            appWorlds: appWorlds,
            registry: state.registry,
            renderCaptureService: renderCaptureService,
            logger: state.logger
        )
        if configuration.enableHTTP {
            let controller = AdaMCPHTTPServerController(configuration: configuration, runtime: runtime)
            state.httpController = controller

            Task { @MainActor in
                do {
                    let endpointURL = try await controller.start(configuration: configuration)
                    self.state.runtimeResource.updateHTTP(endpointURL: endpointURL, isRunning: true)
                } catch {
                    self.state.logger.error("Failed to start MCP HTTP server: \(error.localizedDescription)")
                    self.state.runtimeResource.updateHTTP(endpointURL: nil, isRunning: false)
                }
            }
        } else {
            state.runtimeResource.updateHTTP(endpointURL: nil, isRunning: false)
        }

        if configuration.enableStdio {
            let controller = AdaMCPStdioServerController(runtime: runtime)
            state.stdioController = controller

            Task { @MainActor in
                do {
                    try await controller.start(configuration: configuration)
                    self.state.runtimeResource.updateStdio(isRunning: true)
                } catch {
                    self.state.logger.error("Failed to start MCP stdio server: \(error.localizedDescription)")
                    self.state.runtimeResource.updateStdio(isRunning: false)
                }
            }
        } else {
            state.runtimeResource.updateStdio(isRunning: false)
        }
    }

    public func destroy(for app: borrowing AppWorlds) {
        Task { @MainActor in
            await self.state.httpController?.stop()
            await self.state.stdioController?.stop()
            self.state.runtimeResource.updateHTTP(endpointURL: nil, isRunning: false)
            self.state.runtimeResource.updateStdio(isRunning: false)
            self.state.httpController = nil
            self.state.stdioController = nil
        }
    }
}
