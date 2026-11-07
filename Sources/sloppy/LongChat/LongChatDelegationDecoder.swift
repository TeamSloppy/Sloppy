import Foundation
import Protocols

enum LongChatDelegationDecoder {
    struct ValidationError: Error {
        let message: String
        let hint: String
    }

    static func decode(_ value: JSONValue?) throws -> LongChatDelegationRequest {
        let data: Data
        switch value {
        case .object:
            data = try JSONEncoder().encode(value)
        case .string(let raw):
            // Keep older clients and restored tool calls compatible.
            data = Data(raw.utf8)
        default:
            throw ValidationError(
                message: "assignment must be an object.",
                hint: "Call long_chat.delegate with assignment: {requestKey: string, title: string, acceptanceCriteria: string, tasks: array}. Correct the arguments; no worker was started.")
        }
        return normalized(try JSONDecoder().decode(LongChatDelegationRequest.self, from: data))
    }

    static func normalized(_ request: LongChatDelegationRequest) -> LongChatDelegationRequest {
        var request = request
        for index in request.tasks.indices {
            request.tasks[index].reuseSessionId = optionalID(request.tasks[index].reuseSessionId)
            request.tasks[index].projectId = optionalID(request.tasks[index].projectId)
        }
        return request
    }

    static func optionalID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
