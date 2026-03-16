import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

// MARK: - Helpers

private func makeChannelSnapshot(channelId: String = "ch1") -> ChannelSnapshot {
    ChannelSnapshot(
        channelId: channelId,
        messages: [],
        contextUtilization: 0,
        activeWorkerIds: [],
        lastDecision: nil
    )
}

private func makeWorkerSnapshot(
    workerId: String = UUID().uuidString,
    channelId: String = "ch1",
    status: WorkerStatus = .running
) -> WorkerSnapshot {
    WorkerSnapshot(
        workerId: workerId,
        channelId: channelId,
        taskId: "t1",
        status: status,
        mode: .interactive,
        tools: [],
        latestReport: nil,
        startedAt: nil
    )
}

private actor SignalCollector {
    var events: [EventEnvelope] = []
    func record(_ event: EventEnvelope) { events.append(event) }
    func ofType(_ type: MessageType) -> [EventEnvelope] { events.filter { $0.messageType == type } }
}

// MARK: - Readiness flag

@Test func visorIsNotReadyBeforeFirstTick() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)
    let ready = await visor.isReady
    #expect(ready == false)
}

@Test func visorIsReadyAfterFirstTick() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    await visor.startSupervision(
        tickInterval: .milliseconds(100),
        workerTimeoutSeconds: 600,
        branchTimeoutSeconds: 60,
        maintenanceIntervalSeconds: 3600,
        decayRatePerDay: 0.05,
        pruneImportanceThreshold: 0.1,
        pruneMinAgeDays: 30,
        snapshotProvider: { ([], []) },
        branchProvider: { [] },
        branchForceTimeout: { _ in }
    )

    try? await Task.sleep(for: .milliseconds(500))
    await visor.stopSupervision()

    let ready = await visor.isReady
    #expect(ready == true)
}

// MARK: - Signal: channel degraded

@Test func visorPublishesChannelDegradedSignal() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    let stream = await bus.subscribe()
    let collector = SignalCollector()
    let collectTask = Task {
        for await event in stream {
            await collector.record(event)
        }
    }

    let failureEvent = EventEnvelope(
        messageType: .workerFailed,
        channelId: "ch-degraded",
        payload: .object([:])
    )

    await visor.recordEvent(failureEvent)
    await visor.recordEvent(failureEvent)
    await visor.recordEvent(failureEvent)

    await visor.checkSignals(
        channelDegradedFailureCount: 3,
        channelDegradedWindowSeconds: 600,
        idleThresholdSeconds: 1_800_000
    )

    try? await Task.sleep(for: .milliseconds(50))
    collectTask.cancel()

    let signals = await collector.ofType(.visorSignalChannelDegraded)
    #expect(signals.count == 1)
    #expect(signals.first?.channelId == "ch-degraded")
}

@Test func visorSkipsChannelDegradedBelowThreshold() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    let stream = await bus.subscribe()
    let collector = SignalCollector()
    let collectTask = Task {
        for await event in stream {
            await collector.record(event)
        }
    }

    let failureEvent = EventEnvelope(messageType: .workerFailed, channelId: "ch-ok", payload: .object([:])) 
    await visor.recordEvent(failureEvent)
    await visor.recordEvent(failureEvent)

    await visor.checkSignals(
        channelDegradedFailureCount: 3,
        channelDegradedWindowSeconds: 600,
        idleThresholdSeconds: 1_800_000
    )

    try? await Task.sleep(for: .milliseconds(50))
    collectTask.cancel()

    let signals = await collector.ofType(.visorSignalChannelDegraded)
    #expect(signals.isEmpty)
}

@Test func visorClearsFailureWindowAfterSignal() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    let stream = await bus.subscribe()
    let collector = SignalCollector()
    let collectTask = Task {
        for await event in stream {
            await collector.record(event)
        }
    }

    let failureEvent = EventEnvelope(messageType: .workerFailed, channelId: "ch-x", payload: .object([:])) 
    await visor.recordEvent(failureEvent)
    await visor.recordEvent(failureEvent)
    await visor.recordEvent(failureEvent)

    await visor.checkSignals(channelDegradedFailureCount: 3, channelDegradedWindowSeconds: 600, idleThresholdSeconds: 1_800_000)
    await visor.checkSignals(channelDegradedFailureCount: 3, channelDegradedWindowSeconds: 600, idleThresholdSeconds: 1_800_000)

    try? await Task.sleep(for: .milliseconds(50))
    collectTask.cancel()

    let signals = await collector.ofType(.visorSignalChannelDegraded)
    #expect(signals.count == 1)
}

// MARK: - Signal: idle

@Test func visorPublishesIdleSignalWhenInactive() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    let stream = await bus.subscribe()
    let collector = SignalCollector()
    let collectTask = Task {
        for await event in stream {
            await collector.record(event)
        }
    }

    await visor.checkSignals(
        channelDegradedFailureCount: 3,
        channelDegradedWindowSeconds: 600,
        idleThresholdSeconds: 0
    )

    try? await Task.sleep(for: .milliseconds(50))
    collectTask.cancel()

    let signals = await collector.ofType(.visorSignalIdle)
    #expect(signals.count == 1)
}

@Test func visorSkipsIdleSignalWhenRecentlyActive() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory)

    let stream = await bus.subscribe()
    let collector = SignalCollector()
    let collectTask = Task {
        for await event in stream {
            await collector.record(event)
        }
    }

    let activityEvent = EventEnvelope(messageType: .channelMessageReceived, channelId: "ch1", payload: .object([:])) 
    await visor.recordEvent(activityEvent)

    await visor.checkSignals(
        channelDegradedFailureCount: 3,
        channelDegradedWindowSeconds: 600,
        idleThresholdSeconds: 1_800_000
    )

    try? await Task.sleep(for: .milliseconds(50))
    collectTask.cancel()

    let signals = await collector.ofType(.visorSignalIdle)
    #expect(signals.isEmpty)
}

// MARK: - Visor chat

@Test func visorAnswerReturnsBulletinDigestWhenNoProvider() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(eventBus: bus, memoryStore: memory, completionProvider: nil)

    let bulletin = await visor.generateBulletin(channels: [], workers: [])
    let answer = await visor.answer(question: "What is the system status?", channels: [], workers: [])

    #expect(answer == bulletin.digest)
}

@Test func visorAnswerUsesCompletionProvider() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(
        eventBus: bus,
        memoryStore: memory,
        completionProvider: { prompt, _ in
            "Visor says: \(prompt.prefix(10))..."
        }
    )

    let answer = await visor.answer(
        question: "Are there active workers?",
        channels: [makeChannelSnapshot()],
        workers: [makeWorkerSnapshot()]
    )

    #expect(answer.hasPrefix("Visor says:"))
}
