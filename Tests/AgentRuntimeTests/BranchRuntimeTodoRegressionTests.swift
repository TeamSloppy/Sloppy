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
    await withTaskGroup(of: EventEnvelope?.self) { group in
        group.addTask {
            for await event in stream {
                if event.messageType == type {
                    return event
                }
            }
            return nil
        }

        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }

        let event = await group.next() ?? nil
        group.cancelAll()
        return event
    }
}
