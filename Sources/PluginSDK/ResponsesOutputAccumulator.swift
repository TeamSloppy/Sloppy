import Foundation

/// Replayable provider output for stateless Responses tool rounds. Keep opaque reasoning and
/// message phase exactly as returned; rebuilding only tool calls loses the model's working state.
struct ResponsesOutputAccumulator {
    private var completedItems: [Int: [String: Any]] = [:]
    private var responseOutput: [[String: Any]]?

    var items: [[String: Any]] {
        let output = responseOutput ?? completedItems.keys.sorted().compactMap { completedItems[$0] }
        return output.map { item in
            var item = item
            if item["type"] as? String == "function_call",
               !ResponsesFunctionCallAccumulator.isJSONObject(item["arguments"] as? String ?? "") {
                // The delegate reports malformed arguments to the model. Replay a valid object
                // so that the corrective tool output can reach it instead of failing HTTP validation.
                item["arguments"] = "{}"
            }
            return item
        }
    }

    mutating func consume(line: String) {
        guard line.hasPrefix("data: "),
              let data = String(line.dropFirst(6)).data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        switch event["type"] as? String {
        case "response.output_item.done":
            if let index = event["output_index"] as? Int, let item = event["item"] as? [String: Any] {
                completedItems[index] = item
            }
        case "response.completed":
            if let response = event["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                responseOutput = output
            }
        default:
            break
        }
    }
}
