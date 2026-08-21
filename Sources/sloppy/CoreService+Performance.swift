import AgentRuntime

extension CoreService {
    public func runtimePerformanceSnapshot(limit: Int = 60) async -> RuntimePerformanceSnapshot {
        await runtime.performanceSnapshot(limit: limit)
    }
}
