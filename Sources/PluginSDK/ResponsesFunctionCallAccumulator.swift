import Foundation

/// A function call emitted by the Responses API stream.
struct ResponsesFunctionCall: Sendable, Equatable {
    var callId: String
    var name: String
    var arguments: String
}

/// Reassembles function calls from Responses API SSE events.
///
/// The model may emit several function calls in one response. Each call has its own
/// `output_index` / `item_id`, and events for different calls can interleave, so state is
/// tracked per item and the final order follows the order in which calls were announced.
struct ResponsesFunctionCallAccumulator {
    private struct Entry {
        var itemId: String?
        var outputIndex: Int?
        var call: ResponsesFunctionCall
        /// Authoritative arguments from `.done` events; replaces streamed deltas when present.
        var finalArguments: String?
    }

    private var entries: [Entry] = []

    /// Calls in the order they were announced, with the best-known arguments.
    var calls: [ResponsesFunctionCall] {
        entries.map { entry in
            var call = entry.call
            if let final = entry.finalArguments {
                call.arguments = final
            }
            return call
        }
    }

    /// Feeds one SSE line. Returns `true` when the line was a function-call event.
    @discardableResult
    mutating func consume(line: String) -> Bool {
        guard line.hasPrefix("data: "),
              let data = String(line.dropFirst(6)).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return false }

        let outputIndex = obj["output_index"] as? Int
        switch type {
        case "response.output_item.added":
            guard let item = obj["item"] as? [String: Any], item["type"] as? String == "function_call" else {
                return false
            }
            let itemId = item["id"] as? String
            guard let callId = (item["call_id"] as? String) ?? itemId,
                  let name = item["name"] as? String
            else { return false }
            let initial = item["arguments"] as? String ?? ""
            entries.append(Entry(
                itemId: itemId,
                outputIndex: outputIndex,
                call: ResponsesFunctionCall(callId: callId, name: name, arguments: initial),
                finalArguments: nil
            ))
            return true
        case "response.function_call_arguments.delta":
            guard let delta = obj["delta"] as? String,
                  let index = entryIndex(itemId: obj["item_id"] as? String, outputIndex: outputIndex)
            else { return false }
            entries[index].call.arguments.append(delta)
            return true
        case "response.function_call_arguments.done":
            guard let index = entryIndex(itemId: obj["item_id"] as? String, outputIndex: outputIndex) else {
                return false
            }
            if let arguments = obj["arguments"] as? String {
                entries[index].finalArguments = arguments
            }
            return true
        case "response.output_item.done":
            guard let item = obj["item"] as? [String: Any], item["type"] as? String == "function_call" else {
                return false
            }
            let itemId = item["id"] as? String
            if let index = entryIndex(itemId: itemId, outputIndex: outputIndex) {
                if let arguments = item["arguments"] as? String, !arguments.isEmpty {
                    entries[index].finalArguments = arguments
                }
            } else if let callId = (item["call_id"] as? String) ?? itemId, let name = item["name"] as? String {
                // `added` was missed; the completed item still carries everything needed.
                entries.append(Entry(
                    itemId: itemId,
                    outputIndex: outputIndex,
                    call: ResponsesFunctionCall(callId: callId, name: name, arguments: item["arguments"] as? String ?? ""),
                    finalArguments: nil
                ))
            }
            return true
        default:
            return false
        }
    }

    private func entryIndex(itemId: String?, outputIndex: Int?) -> Int? {
        if let itemId, let index = entries.firstIndex(where: { $0.itemId == itemId }) {
            return index
        }
        if let outputIndex, let index = entries.firstIndex(where: { $0.outputIndex == outputIndex }) {
            return index
        }
        // Events without identifiers can only refer to the most recent call.
        if itemId == nil, outputIndex == nil, !entries.isEmpty {
            return entries.count - 1
        }
        return nil
    }

    /// True when `arguments` decodes to a JSON object.
    static func isJSONObject(_ arguments: String) -> Bool {
        guard let data = arguments.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else { return false }
        return value is [String: Any]
    }
}
