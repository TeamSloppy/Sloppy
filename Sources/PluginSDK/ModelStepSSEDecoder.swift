import Foundation
import AnyLanguageModel

struct ModelStepSSEDecoder {
    private var decoder = AnyLanguageModel.StepSSEDecoder()
    mutating func consume(_ data: Data) throws -> [String] {
        do { return try decoder.consume(data) } catch { throw LibraryModelStepBridge.failure(error) }
    }
    mutating func finish() throws -> [String] {
        do { return try decoder.finish() } catch { throw LibraryModelStepBridge.failure(error) }
    }
}
