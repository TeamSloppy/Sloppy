import Foundation
import Testing
@testable import AgentRuntime

@Suite("Runtime performance telemetry")
struct RuntimePerformanceTelemetryTests {
    @Test("Snapshot aggregates latency, throughput, and tool parallelism")
    func snapshotAggregatesSamples() async {
        let telemetry = RuntimePerformanceTelemetry(capacity: 4)
        await telemetry.record(sample(ttft: 100, duration: 1_000, delta: 20, cps: 120, tools: 2, parallel: 2, failed: 0))
        await telemetry.record(sample(ttft: 300, duration: 2_000, delta: 40, cps: 80, tools: 3, parallel: 3, failed: 1))

        let snapshot = await telemetry.snapshot()

        #expect(snapshot.samples.count == 2)
        #expect(snapshot.summary.averageTimeToFirstTokenMs == 200)
        #expect(snapshot.summary.p95TimeToFirstTokenMs == 300)
        #expect(snapshot.summary.averageDeltaIntervalMs == 30)
        #expect(snapshot.summary.averageGenerationDurationMs == 1_500)
        #expect(snapshot.summary.averageCharactersPerSecond == 100)
        #expect(snapshot.summary.totalToolCalls == 5)
        #expect(snapshot.summary.peakParallelToolCalls == 3)
        #expect(snapshot.summary.failedToolCalls == 1)
    }

    @Test("Capacity keeps only the newest samples")
    func capacityKeepsNewestSamples() async {
        let telemetry = RuntimePerformanceTelemetry(capacity: 2)
        await telemetry.record(sample(ttft: 1, duration: 1, delta: nil, cps: 1, tools: 0, parallel: 0, failed: 0))
        await telemetry.record(sample(ttft: 2, duration: 2, delta: nil, cps: 2, tools: 0, parallel: 0, failed: 0))
        await telemetry.record(sample(ttft: 3, duration: 3, delta: nil, cps: 3, tools: 0, parallel: 0, failed: 0))

        let snapshot = await telemetry.snapshot(limit: 10)

        #expect(snapshot.samples.map(\.timeToFirstTokenMs) == [2, 3])
    }

    private func sample(
        ttft: Int,
        duration: Int,
        delta: Int?,
        cps: Double,
        tools: Int,
        parallel: Int,
        failed: Int
    ) -> RuntimePerformanceSample {
        RuntimePerformanceSample(
            channelId: "agent:test:session:test",
            model: "test-model",
            timeToFirstTokenMs: ttft,
            generationDurationMs: duration,
            outputCharacters: 100,
            streamChunks: 10,
            averageDeltaIntervalMs: delta,
            maxDeltaIntervalMs: delta,
            charactersPerSecond: cps,
            toolCallCount: tools,
            toolBatchCount: tools > 0 ? 1 : 0,
            maxParallelToolCalls: parallel,
            averageToolDurationMs: tools > 0 ? 50 : nil,
            failedToolCalls: failed
        )
    }
}
