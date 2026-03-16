import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

// MARK: - Helpers

private actor CallTracker {
    var callCount = 0
    var lastPrompt: String?

    func record(prompt: String) {
        callCount += 1
        lastPrompt = prompt
    }

    func count() -> Int { callCount }
    func prompt() -> String? { lastPrompt }
}

private func makeSnapshot(channelId: String) -> ChannelSnapshot {
    ChannelSnapshot(channelId: channelId, messages: [], contextUtilization: 0, activeWorkerIds: [], lastDecision: nil)
}

private func makeWorker(workerId: String, channelId: String, status: WorkerStatus = .running) -> WorkerSnapshot {
    WorkerSnapshot(workerId: workerId, channelId: channelId, taskId: "t1", status: status, mode: .interactive, tools: [], latestReport: nil)
}

// MARK: - LLM synthesis

@Test
func visorUsesLLMSynthesisWhenProviderAvailable() async throws {
    let tracker = CallTracker()
    let provider: @Sendable (String, Int) async -> String? = { prompt, _ in
        await tracker.record(prompt: prompt)
        return "System has 2 active channels and 1 running worker. No urgent tasks."
    }

    let visor = Visor(
        eventBus: EventBus(),
        memoryStore: InMemoryMemoryStore(),
        completionProvider: provider,
        bulletinMaxWords: 100
    )

    let channels = [makeSnapshot(channelId: "ch1"), makeSnapshot(channelId: "ch2")]
    let workers = [makeWorker(workerId: "w1", channelId: "ch1")]

    let bulletin = await visor.generateBulletin(channels: channels, workers: workers, taskSummary: "Task A in progress")

    #expect(await tracker.count() == 1)
    let prompt = await tracker.prompt()
    #expect(prompt?.contains("Channel Activity") == true)
    #expect(prompt?.contains("Active Workers") == true)
    #expect(prompt?.contains("Task Status") == true)
    #expect(bulletin.digest == "System has 2 active channels and 1 running worker. No urgent tasks.")
    #expect(bulletin.headline.contains("channels"))
}

// MARK: - Fallback

@Test
func visorFallsBackToProgrammaticBulletinWhenNoProvider() async throws {
    let visor = Visor(eventBus: EventBus(), memoryStore: InMemoryMemoryStore(), completionProvider: nil)
    let channels = [makeSnapshot(channelId: "ch1")]

    let bulletin = await visor.generateBulletin(channels: channels, workers: [])

    #expect(!bulletin.digest.isEmpty)
    #expect(bulletin.digest.contains("Active channels: 1"))
    #expect(bulletin.headline.contains("channels"))
}

@Test
func visorFallsBackToProgrammaticBulletinWhenLLMFails() async throws {
    let provider: @Sendable (String, Int) async -> String? = { _, _ in nil }
    let visor = Visor(eventBus: EventBus(), memoryStore: InMemoryMemoryStore(), completionProvider: provider)
    let channels = [makeSnapshot(channelId: "ch1")]

    let bulletin = await visor.generateBulletin(channels: channels, workers: [])

    #expect(!bulletin.digest.isEmpty)
    #expect(bulletin.digest.contains("Active channels: 1"))
}

// MARK: - Deduplication

@Test
func visorSkipsLLMCallWhenStateUnchanged() async throws {
    let tracker = CallTracker()
    let provider: @Sendable (String, Int) async -> String? = { _, _ in
        await tracker.record(prompt: "")
        return "Stable state briefing."
    }

    let visor = Visor(eventBus: EventBus(), memoryStore: InMemoryMemoryStore(), completionProvider: provider)
    let channels = [makeSnapshot(channelId: "ch1")]

    let first = await visor.generateBulletin(channels: channels, workers: [])
    let second = await visor.generateBulletin(channels: channels, workers: [])

    #expect(await tracker.count() == 1)
    #expect(first.id == second.id)
    #expect(first.digest == second.digest)
}

@Test
func visorRunsLLMAgainWhenStateChanges() async throws {
    let tracker = CallTracker()
    let provider: @Sendable (String, Int) async -> String? = { _, _ in
        await tracker.record(prompt: "")
        return "Updated briefing."
    }

    let visor = Visor(eventBus: EventBus(), memoryStore: InMemoryMemoryStore(), completionProvider: provider)

    let channels1 = [makeSnapshot(channelId: "ch1")]
    let channels2 = [makeSnapshot(channelId: "ch1"), makeSnapshot(channelId: "ch2")]

    _ = await visor.generateBulletin(channels: channels1, workers: [])
    _ = await visor.generateBulletin(channels: channels2, workers: [])

    #expect(await tracker.count() == 2)
}

// MARK: - Bulletin storage

@Test
func visorStoresTwoBulletinsWhenStateChanges() async throws {
    let visor = Visor(eventBus: EventBus(), memoryStore: InMemoryMemoryStore(), completionProvider: nil)

    _ = await visor.generateBulletin(channels: [makeSnapshot(channelId: "ch1")], workers: [])
    _ = await visor.generateBulletin(channels: [makeSnapshot(channelId: "ch1"), makeSnapshot(channelId: "ch2")], workers: [])

    let bulletins = await visor.listBulletins()
    #expect(bulletins.count == 2)
}

// MARK: - bulletinMaxWords in prompt

@Test
func visorIncludesBulletinMaxWordsInSynthesisPrompt() async throws {
    let tracker = CallTracker()
    let provider: @Sendable (String, Int) async -> String? = { prompt, _ in
        await tracker.record(prompt: prompt)
        return "Brief."
    }

    let visor = Visor(
        eventBus: EventBus(),
        memoryStore: InMemoryMemoryStore(),
        completionProvider: provider,
        bulletinMaxWords: 250
    )

    _ = await visor.generateBulletin(channels: [makeSnapshot(channelId: "c1")], workers: [])

    let prompt = await tracker.prompt()
    #expect(prompt?.contains("250") == true)
}
