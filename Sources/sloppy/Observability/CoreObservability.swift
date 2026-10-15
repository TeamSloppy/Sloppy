import Foundation
import Logging
#if canImport(OTel)
import OTel
import ServiceLifecycle
#endif
import Metrics
import Tracing

/// Optional OTLP exporters. HTTP and runtime instrumentation stays no-op until enabled.
actor CoreObservability {
    static let shared = CoreObservability()
    #if canImport(OTel)
    private var group: ServiceGroup?
    private var task: Task<Void, Never>?
    #endif

    func start(logger: Logger) {
        #if canImport(OTel)
        guard task == nil, ProcessInfo.processInfo.environment["SLOPPY_OTEL_ENABLED"] == "1" else { return }
        do {
            var configuration = OTel.Configuration.default
            configuration.serviceName = "sloppy-core"
            configuration.logs.enabled = false
            configuration.metrics.otlpExporter.protocol = .httpProtobuf
            configuration.traces.otlpExporter.protocol = .httpProtobuf
            configuration.metrics.exportInterval = .seconds(15)
            let metrics = try OTel.makeMetricsBackend(configuration: configuration)
            let tracing = try OTel.makeTracingBackend(configuration: configuration)
            MetricsSystem.bootstrap(metrics.factory)
            InstrumentationSystem.bootstrap(tracing.factory)
            let group = ServiceGroup(services: [metrics.service, tracing.service], logger: logger)
            self.group = group
            task = Task {
                do { try await group.run() }
                catch { logger.warning("OpenTelemetry exporters stopped: \(error)") }
            }
            logger.info("OpenTelemetry metrics and traces enabled")
        } catch {
            logger.warning("Could not enable OpenTelemetry: \(error)")
        }
        #else
        if ProcessInfo.processInfo.environment["SLOPPY_OTEL_ENABLED"] == "1" {
            logger.warning("OpenTelemetry exporters are unavailable on this platform")
        }
        #endif
    }

    func shutdown() async {
        #if canImport(OTel)
        await group?.triggerGracefulShutdown()
        await task?.value
        // Global SDKs can only be bootstrapped once in this process.
        #endif
    }
}
