import Foundation

/// Each invocation still performs one generation. A structured API rejection changes
/// the next attempt's transport; AgentLoop owns the retry, accounting and deadline.
actor OpenAIFormatStepProvider: ModelStepProvider {
    private let chat: NativeHTTPModelStepProvider
    private let responses: NativeHTTPModelStepProvider
    private var usesResponses = false

    init(chat: NativeHTTPModelStepProvider, responses: NativeHTTPModelStepProvider) {
        self.chat = chat; self.responses = responses
    }

    private func prepared(_ request: ModelStepRequest) -> (NativeHTTPModelStepProvider, ModelStepRequest, Bool) {
        // A fresh process can recover the format from its own durable continuation.
        if request.messages.contains(where: {
            $0.continuation?.providerId == responses.providerID && $0.continuation?.modelId == responses.model &&
                $0.continuation?.format == "responses-v1"
        }) { usesResponses = true }
        var normalized = request
        if usesResponses {
            normalized.messages = request.messages.map { message in
                var message = message
                if let saved = message.continuation, saved.providerId == chat.providerID,
                   saved.modelId == chat.model, saved.format == "chat-completions-v1" {
                    // Preserve typed text/calls/results. Chat-only opaque tokens cannot
                    // be replayed under Responses; canonical history remains unchanged.
                    message.continuation = nil
                }
                return message
            }
        }
        return (usesResponses ? responses : chat, normalized, usesResponses)
    }

    private func transition(after failure: ModelStepFailure, wasResponses: Bool) -> Bool {
        guard !wasResponses, failure.category == .provider, failure.stage == .request else { return false }
        let unsupported = ["unsupported_model", "unsupported_tools"].contains(failure.code) ||
            (["unsupported_parameter", "http_400", "http_404"].contains(failure.code) &&
             ["model", "tools"].contains(failure.parameter ?? ""))
        guard unsupported else { return false }
        usesResponses = true
        return true
    }

    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let task = Task {
                let (provider, normalized, wasResponses) = await self.prepared(request)
                do {
                    for try await event in provider.streamStep(normalized) {
                        try await ModelStepEventDelivery.yield(event, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    var failure = LibraryModelStepBridge.failure(error)
                    if await self.transition(after: failure, wasResponses: wasResponses) { failure.retryable = true }
                    continuation.finish(throwing: failure)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
