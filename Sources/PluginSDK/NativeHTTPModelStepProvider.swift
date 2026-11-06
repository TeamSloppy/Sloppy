import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

import AnyLanguageModel

typealias ModelStepHTTPFormat = AnyLanguageModel.StepHTTPFormat

struct NativeHTTPModelStepProvider: ModelStepProvider {
    let providerID: String
    let model: String
    let baseURL: URL
    let token: @Sendable () -> String
    let refresh: (@Sendable () async throws -> Void)?
    let session: URLSession
    let instructions: String
    var format: ModelStepHTTPFormat = .responses
    var thinkingValues: [Protocols.JSONValue]? = nil
    var nativeCodeAssist: GeminiModelProvider.NativeCodeAssistSettings? = nil

    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        let settings = nativeCodeAssist.map {
            StepCodeAssistSettings(baseURL: $0.baseURL, projectID: $0.projectID, headers: $0.headers,
                userAgent: $0.userAgent, refreshCredentials: $0.refreshCredentials)
        }
        // Values are bridged before starting I/O so invalid input produces a typed preparation failure.
        do {
            let thinking: [StepJSONValue]? = try thinkingValues.map { try LibraryModelStepBridge.convert($0) }
            let provider = HTTPModelStepProvider(providerID: providerID, model: model, baseURL: baseURL,
                token: token, refresh: refresh, session: session, instructions: instructions, format: format,
                thinkingValues: thinking, nativeCodeAssist: settings,
                cacheKey: { "sloppy-step-" + ModelStepHTTPTransport.cacheKeyDigest(providerID + "/" + $0.cacheScope) },
                requestTransform: { outgoing, _ in
                    var outgoing = outgoing
                    if format == .anthropic {
                        outgoing.setValue(nil, forHTTPHeaderField: "x-api-key")
                        for (field, value) in OAuthAnthropicAuthHeaders.make(apiKey: token(), baseURL: baseURL,
                            apiVersion: OAuthAnthropicAuthHeaders.defaultAPIVersion, additionalBetas: nil) {
                            outgoing.setValue(value, forHTTPHeaderField: field)
                        }
                    }
                    return outgoing
                })
            return LibraryModelStepProvider(provider: provider).streamStep(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: LibraryModelStepBridge.failure(error)) }
        }
    }
}
