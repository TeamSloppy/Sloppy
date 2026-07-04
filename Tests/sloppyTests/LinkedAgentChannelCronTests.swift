import AnyLanguageModel
import Foundation
import Testing
@testable import PluginSDK
@testable import Protocols
@testable import sloppy

private struct DelegateAwareToolCallingLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let toolName: String
    let successText: String
    let missingDelegateText: String

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        guard type == String.self else {
            fatalError("DelegateAwareToolCallingLanguageModel only supports String responses")
        }

        guard let delegate = session.toolExecutionDelegate else {
            return LanguageModelSession.Response(
                content: missingDelegateText as! Content,
                rawContent: GeneratedContent(missingDelegateText),
                transcriptEntries: []
            )
        }

        let toolCall = Transcript.ToolCall(
            id: UUID().uuidString,
            toolName: toolName,
            arguments: GeneratedContent("")
        )
        await delegate.didGenerateToolCalls([toolCall], in: session)
        let decision = await delegate.toolCallDecision(for: toolCall, in: session)

        var entries: [Transcript.Entry] = [.toolCalls(Transcript.ToolCalls([toolCall]))]
        if case .provideOutput(let segments) = decision {
            let output = Transcript.ToolOutput(id: toolCall.id, toolName: toolCall.toolName, segments: segments)
            await delegate.didExecuteToolCall(toolCall, output: output, in: session)
            entries.append(.toolOutput(output))
        }

        return LanguageModelSession.Response(
            content: successText as! Content,
            rawContent: GeneratedContent(successText),
            transcriptEntries: ArraySlice(entries)
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                do {
                    let response = try await respond(
                        within: session,
                        to: prompt,
                        generating: type,
                        includeSchemaInPrompt: includeSchemaInPrompt,
                        options: options
                    )
                    continuation.yield(.init(content: response.content.asPartiallyGenerated(), rawContent: response.rawContent))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

private actor DelegateAwareToolCallingModelProvider: ModelProvider {
    nonisolated let id: String = "delegate-aware-tool-calling"
    nonisolated let supportedModels: [String] = ["mock:linked-agent"]

    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        DelegateAwareToolCallingLanguageModel(
            toolName: "system.list_tools",
            successText: "tool delegate used",
            missingDelegateText: "missing tool delegate"
        )
    }
}

private actor CronMessagePosterProbe {
    private var requests: [(channelId: String, request: ChannelMessageRequest)] = []

    func record(channelId: String, request: ChannelMessageRequest) {
        requests.append((channelId, request))
    }

    func snapshot() -> [(channelId: String, request: ChannelMessageRequest)] {
        requests
    }
}

@Suite("Linked agent channel cron")
struct LinkedAgentChannelCronTests {
    @Test("postChannelMessage uses linked agent tool delegate for agent-bound channels")
    func postChannelMessageUsesLinkedAgentToolDelegate() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let agentID = "cron-linked-\(UUID().uuidString.lowercased())"
        _ = try await service.createAgent(
            AgentCreateRequest(
                id: agentID,
                displayName: "Cron Linked",
                role: "Use tools when invoked from a linked channel."
            )
        )
        await service.overrideModelProviderForTests(DelegateAwareToolCallingModelProvider(), defaultModel: "mock:linked-agent")

        let decision = await service.postChannelMessage(
            channelId: "agent:\(agentID)",
            request: ChannelMessageRequest(
                userId: "system_cron_test",
                content: "List your tools."
            )
        )

        #expect(decision.action == .respond)

        let snapshot = await service.getChannelState(channelId: "agent:\(agentID)")
        let systemReply = snapshot?.messages.last(where: { $0.userId == "system" })?.content
        #expect(systemReply == "tool delegate used")
    }

    @Test("cron runner posts due tasks through injected channel message poster")
    func cronRunnerPostsDueTasksThroughInjectedPoster() async throws {
        let store = InMemoryCorePersistenceBuilder().makeStore(config: .test)
        let cronTask = AgentCronTask(
            id: "cron-1",
            agentId: "agent-1",
            channelId: "agent:agent-1",
            schedule: "* * * * *",
            command: "Ping the linked agent",
            enabled: true
        )
        await store.saveCronTask(cronTask)

        let probe = CronMessagePosterProbe()
        let runner = CronRunner(store: store) { channelId, request in
            await probe.record(channelId: channelId, request: request)
        }

        await runner.triggerImmediately(date: Date(timeIntervalSince1970: 1_704_067_200))

        let requests = await probe.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.channelId == "agent:agent-1")
        #expect(requests.first?.request.userId == "system_cron")
        #expect(requests.first?.request.content.contains("CRON TRIGGER: Ping the linked agent") == true)
    }
}
