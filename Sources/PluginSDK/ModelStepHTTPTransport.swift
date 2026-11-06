import Foundation
import AnyLanguageModel
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias ModelStepHTTPEvent = AnyLanguageModel.StepHTTPEvent
typealias ModelStepHTTPStream = AnyLanguageModel.StepHTTPStream
struct ModelStepHTTPTransport: Sendable {
    let session: URLSession
    static func cacheKeyDigest(_ text: String) -> String { AnyLanguageModel.StepHTTPTransport.cacheKeyDigest(text) }
    static func failure(status: Int, headers: [String: String], body: Data) -> ModelStepFailure {
        LibraryModelStepBridge.failure(AnyLanguageModel.StepHTTPTransport.failure(status: status, headers: headers, body: body))
    }
    static func normalizedFailure(_ error: any Error) -> ModelStepFailure { LibraryModelStepBridge.failure(error) }
    func stream(_ request: URLRequest) -> ModelStepHTTPStream { AnyLanguageModel.StepHTTPTransport(session: session).stream(request) }
}
