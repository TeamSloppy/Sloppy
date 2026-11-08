import Foundation
import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SloppyModelStepRequest: Codable, Sendable {
    public var schemaVersion: Int
    public var request: ModelStepRequest
    public var stream: Bool?
    public init(request: ModelStepRequest, stream: Bool = true) {
        schemaVersion = 1; self.request = request; self.stream = stream
    }
}

/// Correlation belongs to the complete remote result, including a typed failure.
public struct SloppyModelStepResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var runId: String
    public var userTurnId: String
    public var stepId: String
    public var attemptId: String
    public var generation: Int
    public var model: String
    public var response: ModelStepResponse?
    public var failure: ModelStepFailure?
    public init(request: ModelStepRequest, response: ModelStepResponse? = nil, failure: ModelStepFailure? = nil) {
        schemaVersion = 1; runId = request.runId; userTurnId = request.userTurnId
        stepId = request.stepId; attemptId = request.attemptId; generation = request.generation
        model = request.model; self.response = response; self.failure = failure
    }
    public func validated(for request: ModelStepRequest) throws -> ModelStepResponse {
        guard schemaVersion == 1, runId == request.runId, userTurnId == request.userTurnId,
              stepId == request.stepId, attemptId == request.attemptId, generation == request.generation,
              model == request.model, (response == nil) != (failure == nil) else {
            throw ModelStepFailure(category: .protocolViolation, code: "invalid_remote_step_result",
                message: "The remote result has an unsupported version or does not match its request.")
        }
        if let failure { throw failure }
        guard let response else { throw ModelStepFailure(category: .protocolViolation, code: "missing_remote_final", message: "The remote step has no final response.") }
        return response
    }
}

public typealias SloppyModelStepTransport = @Sendable (SloppyModelStepRequest) async throws -> SloppyModelStepResponse

/// A remote model never receives executable tools. The caller retains the loop and effect owner.
public struct SloppyModelStepProvider: ModelStepProvider {
    public let model: String
    public let scope: String
    private let transport: SloppyModelStepTransport

    public init(model: String, scope: String, transport: @escaping SloppyModelStepTransport) {
        self.model = model; self.scope = scope; self.transport = transport
    }
    public init(baseURL: String, accessToken: String, model: String, session: URLSession = .shared) throws {
        let url = try SloppyRemoteEndpoint.url(base: baseURL, path: "providers/step")
        self.model = model
        scope = "http:" + ContentDigest.sha256(Data((url.absoluteString + "\n" + accessToken).utf8))
        transport = { input in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 300
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
            // An anonymous remote must not inherit a different credential from the session.
            request.setValue(accessToken.isEmpty ? "" : "Bearer " + accessToken, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(input)
            var status = 0, headers: [String: String] = [:], body = Data()
            var framing = ModelStepSSEDecoder()
            var final: SloppyModelStepResponse?
            var streamed = false
            func receive(_ payload: String) throws {
                guard final == nil else {
                    throw ModelStepFailure(category: .protocolViolation, code: "duplicate_remote_final", message: "The remote step returned more than one final result.")
                }
                final = try JSONDecoder().decode(SloppyModelStepResponse.self, from: Data(payload.utf8))
            }
            for try await event in ModelStepHTTPTransport(session: session).stream(request) {
                switch event {
                case .response(let code, let fields):
                    status = code; headers = fields
                    streamed = code == 200 && fields["content-type"]?.contains("text/event-stream") == true
                case .data(let data):
                    if streamed { for payload in try framing.consume(data) { try receive(payload) } }
                    else { body.append(data) }
                }
            }
            guard status == 200 else {
                if status == 404 || status == 426 {
                    throw ModelStepFailure(category: .unavailable, code: "remote_step_version_unavailable", message: "The remote server does not support this step protocol.")
                }
                throw ModelStepHTTPTransport.failure(status: status, headers: headers, body: body)
            }
            if streamed { for payload in try framing.finish() { try receive(payload) } }
            else { final = try JSONDecoder().decode(SloppyModelStepResponse.self, from: body) }
            guard let final else {
                throw ModelStepFailure(category: .transport, code: "remote_stream_ended_before_final", message: "The remote stream ended without its complete result.", retryable: true)
            }
            return final
        }
    }

    public func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    guard request.model == model, model.hasPrefix("sloppy:") else {
                        throw ModelStepFailure(category: .unavailable, code: "remote_model_mismatch", message: "The remote adapter is bound to another model.")
                    }
                    var remote = request
                    remote.model = String(model.dropFirst("sloppy:".count))
                    remote.cacheScope = scope + ":" + request.cacheScope
                    for index in remote.messages.indices {
                        guard let saved = remote.messages[index].continuation else { continue }
                        guard saved.providerId == "sloppy", saved.modelId == model, saved.format == "sloppy-step-v1",
                              saved.content.asObject?["scope"] == .string(scope),
                              let inner = saved.content.asObject?["inner"] else {
                            throw ModelStepFailure(category: .protocolViolation, code: "incompatible_remote_continuation", message: "Remote continuation is bound to its server, account and model.")
                        }
                        remote.messages[index].continuation = try JSONValueCoder.decode(ModelStepContinuation.self, from: inner)
                    }
                    continuation.yield(.started)
                    var result = try await transport(.init(request: remote)).validated(for: remote)
                    try Task.checkCancellation()
                    if let inner = result.continuation {
                        result.continuation = .init(providerId: "sloppy", modelId: model, format: "sloppy-step-v1",
                            content: .object(["scope": .string(scope), "inner": try JSONValueCoder.encode(inner)]))
                    }
                    if !result.text.isEmpty { continuation.yield(.textDelta(result.text)) }
                    continuation.yield(.final(result)); continuation.finish()
                } catch { continuation.finish(throwing: ModelStepHTTPTransport.normalizedFailure(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
