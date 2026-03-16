import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

// MARK: - streamAnswer: streaming provider path

@Test func visorStreamAnswerYieldsChunksFromStreamingProvider() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()

    let chunks = ["Hello", " World", "!"]
    let visor = Visor(
        eventBus: bus,
        memoryStore: memory,
        completionProvider: nil,
        streamingProvider: { @Sendable _, _ in
            AsyncStream<String> { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    )

    let stream = await visor.streamAnswer(question: "What is happening?", channels: [], workers: [])
    var collected: [String] = []
    for await chunk in stream {
        collected.append(chunk)
    }

    #expect(collected == chunks)
}

@Test func visorStreamAnswerFallsBackToCompletionProviderWhenNoStreamingProvider() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(
        eventBus: bus,
        memoryStore: memory,
        completionProvider: { @Sendable _, _ in "full answer" },
        streamingProvider: nil
    )

    let stream = await visor.streamAnswer(question: "Status?", channels: [], workers: [])
    var collected: [String] = []
    for await chunk in stream {
        collected.append(chunk)
    }

    #expect(collected == ["full answer"])
}

@Test func visorStreamAnswerYieldsBulletinDigestWhenNoProviders() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let visor = Visor(
        eventBus: bus,
        memoryStore: memory,
        completionProvider: nil,
        streamingProvider: nil
    )

    let stream = await visor.streamAnswer(question: "Status?", channels: [], workers: [])
    var collected: [String] = []
    for await chunk in stream {
        collected.append(chunk)
    }

    #expect(collected.count == 1)
    #expect(collected.first == "No bulletin yet.")
}

// MARK: - streamAnswer: after bulletin is set

private actor PromptCapture {
    var value: String?
    func set(_ v: String) { value = v }
}

@Test func visorStreamAnswerUsesBulletinDigestAsContext() async {
    let bus = EventBus()
    let memory = InMemoryMemoryStore()
    let capture = PromptCapture()

    let visor = Visor(
        eventBus: bus,
        memoryStore: memory,
        completionProvider: nil,
        streamingProvider: { @Sendable prompt, _ in
            let c = capture
            return AsyncStream<String> { continuation in
                Task { await c.set(prompt) }
                continuation.yield("ok")
                continuation.finish()
            }
        }
    )

    _ = await visor.generateBulletin(channels: [], workers: [])
    let stream = await visor.streamAnswer(question: "What happened?", channels: [], workers: [])
    for await _ in stream {}
    try? await Task.sleep(for: .milliseconds(50))

    let capturedPrompt = await capture.value
    #expect(capturedPrompt?.contains("Active channels: 0") == true)
}

