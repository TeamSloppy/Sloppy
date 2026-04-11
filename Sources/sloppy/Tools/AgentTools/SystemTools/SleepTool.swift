import AnyLanguageModel
import Foundation
import Protocols

struct SleepTool: CoreTool {
    let domain = "tools"
    let title = "Sleep"
    let status = "fully_functional"
    let name = "tools.sleep"
    let description = "Pause for a given number of seconds before continuing. Use when you need to wait before retrying (for example polling a remote job). Maximum duration is \(SleepTool.maxSeconds) seconds per call."

    /// Upper bound so a single tool call cannot block a worker unbounded.
    static let maxSeconds = 600

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "seconds",
                description: "Wait time in whole seconds (0 through \(Self.maxSeconds)).",
                schema: DynamicGenerationSchema(type: Int.self)
            )
        ])
    }

    func invoke(arguments: [String: JSONValue], context _: ToolContext) async -> ToolInvocationResult {
        guard let rawSeconds = arguments["seconds"] else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`seconds` is required.", retryable: false)
        }

        let seconds: Int
        if let intValue = rawSeconds.asInt {
            seconds = intValue
        } else if let number = rawSeconds.asNumber {
            seconds = Int(number.rounded())
        } else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`seconds` must be a number.", retryable: false)
        }

        guard seconds >= 0 else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`seconds` must be non-negative.", retryable: false)
        }

        guard seconds <= Self.maxSeconds else {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "`seconds` exceeds the maximum allowed (\(Self.maxSeconds) seconds).",
                retryable: false,
                hint: "Use a shorter wait or split the work across multiple steps."
            )
        }

        if seconds > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            } catch is CancellationError {
                return toolFailure(tool: name, code: "cancelled", message: "Sleep was cancelled.", retryable: true)
            } catch {
                return toolFailure(tool: name, code: "sleep_failed", message: "Sleep could not complete.", retryable: true)
            }
        }

        return toolSuccess(tool: name, data: .object([
            "slept_seconds": .number(Double(seconds))
        ]))
    }
}
