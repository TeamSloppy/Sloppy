import AdaEngine
import AdaMCPCore
import AdaMCPServer
import Logging

public struct MCPPlugin: Plugin {
    @MainActor
    final class State: @unchecked Sendable {
        let registry = MCPIntrospectionRegistry()
        let runtimeResource = MCPServerRuntime()
        let logger = Logger(label: "org.adaengine.mcp.plugin")
        var controller: AdaMCPHTTPServerController?
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

        let renderCaptureService = RenderCaptureService(
            appWorlds: app,
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

        let runtime = AdaMCPRuntime(
            appWorlds: app,
            registry: state.registry,
            renderCaptureService: renderCaptureService,
            logger: state.logger
        )
        let controller = AdaMCPHTTPServerController(configuration: configuration, runtime: runtime)
        state.controller = controller

        Task { @MainActor in
            do {
                let endpointURL = try await controller.start(configuration: configuration)
                self.state.runtimeResource.update(endpointURL: endpointURL, isRunning: true)
            } catch {
                self.state.logger.error("Failed to start MCP HTTP server: \(error.localizedDescription)")
                self.state.runtimeResource.update(endpointURL: nil, isRunning: false)
            }
        }
    }

    public func destroy(for app: borrowing AppWorlds) {
        Task { @MainActor in
            await self.state.controller?.stop()
            self.state.runtimeResource.update(endpointURL: nil, isRunning: false)
            self.state.controller = nil
        }
    }
}
