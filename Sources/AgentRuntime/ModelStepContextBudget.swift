import Foundation
import PluginSDK
import Protocols

/// Conservative input pressure, using the same bounded image estimate as existing preparation.
/// Estimation never alters canonical responses, opaque continuation or tool results.
public enum ModelStepContextBudget {
    static func validate(_ request: ModelStepRequest, limits: ModelContextLimits) throws {
        let tokens = try estimate(request)
        let budget = limits.inputBudget(reserving: request.maximumOutputTokens)
        guard tokens <= budget else {
            throw ModelStepFailure(category: .context, code: "context_preflight_exceeded",
                message: "The prepared input needs approximately \(tokens) tokens, exceeding its \(budget)-token model budget. Saved context was retained; no request was sent.",
                stage: .preparation)
        }
    }

    public static func estimate(_ request: ModelStepRequest) throws -> Int {
        let estimator = TokenPressureEstimator()
        var total = 128
        func add(_ value: Int) {
            let next = total.addingReportingOverflow(max(0, value))
            total = next.overflow ? Int.max : next.partialValue
        }
        func count<T: Encodable>(_ value: T) throws {
            add(estimator.estimateTextTokens(String(decoding: try JSONEncoder().encode(value), as: UTF8.self)))
        }
        for message in request.messages {
            add(16)
            add(estimator.estimateTextTokens(message.text))
            for _ in message.images { add(768) }
            if !message.toolCalls.isEmpty { try count(message.toolCalls) }
            if let output = message.toolOutput { try count(output) }
            if let continuation = message.continuation { try count(continuation) }
        }
        for tool in request.tools {
            add(16)
            try count(Protocols.JSONValue.object(["name": .string(tool.name),
                "description": .string(tool.description), "parameters": tool.parameters]))
        }
        return total
    }
}
