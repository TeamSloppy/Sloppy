import Foundation
import Protocols
import AnyLanguageModel

/// Compatibility adapter; provider framing and serialization live in AnyLanguageModel.
public struct AnthropicModelStepCodec {
    private var codec: AnyLanguageModel.AnthropicStepCodec
    public init(providerID: String, modelID: String) {
        codec = .init(providerID: providerID, modelID: modelID)
    }
    public static func requestBody(_ request: ModelStepRequest, model: String, providerID: String, instructions: String) throws -> Data {
        do { return try AnyLanguageModel.AnthropicStepCodec.requestBody(try LibraryModelStepBridge.convert(request), model: model, providerID: providerID, instructions: instructions) }
        catch { throw LibraryModelStepBridge.failure(error) }
    }
    public mutating func consume(_ data: Data) throws -> [ModelStepEvent] {
        do { return try codec.consume(data).map(LibraryModelStepBridge.event) }
        catch { throw LibraryModelStepBridge.failure(error) }
    }
    public mutating func consumeJSON(_ data: Data) throws {
        do { try codec.consumeJSON(data) } catch { throw LibraryModelStepBridge.failure(error) }
    }
    public mutating func finish() throws -> ModelStepResponse {
        do { return try LibraryModelStepBridge.convert(codec.finish()) }
        catch { throw LibraryModelStepBridge.failure(error) }
    }
}
