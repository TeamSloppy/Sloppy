import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

@Test
func branchSpawnDoesNotStoreTodosOrPublishTodoExtensions() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let branchRuntime = BranchRuntime(eventBus: bus, memoryStore: memory)
    let stream = await bus.subscribe()

    let eventTask = Task {
        await firstEvent(matching: .branchSpawned, in: stream)
    }

    _ = await branchRuntime.spawn(
        channelId: "general",
        prompt: """
        research and extract tasks
        - [ ] Ship dashboard cards
        TODO: Ship dashboard cards
        сделай прогон smoke тестов
        """
    )

    let event = await eventTask.value
    #expect(event?.extensions["todos"] == nil)

    let entries = await memory.entries()
    #expect(entries.isEmpty)
}

private func firstEvent(
    matching type: MessageType,
    in stream: AsyncStream<EventEnvelope>,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async -> EventEnvelope? {
    let probe = FirstEventProbe()
    let task = Task {
        for await event in stream {
            if Task.isCancelled {
                break
            }
            if event.messageType == type {
                await probe.record(event)
                break
            }
        }
    }

    let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000.0)
    while Date() < deadline {
        if let event = await probe.value() {
            task.cancel()
            return event
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    task.cancel()
    return await probe.value()
}

private actor FirstEventProbe {
    private var event: EventEnvelope?

    func record(_ event: EventEnvelope) {
        guard self.event == nil else { return }
        self.event = event
    }

    func value() -> EventEnvelope? {
        event
    }
}
