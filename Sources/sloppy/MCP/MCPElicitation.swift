import Foundation
import Protocols

struct MCPElicitation: Sendable {
    let request: PlanInputRequest

    init(serverID: String, packet: JSONValue, allowURL: Bool) throws {
        guard let object = packet.asObject, object["method"]?.asString == "elicitation/create",
              let params = object["params"]?.asObject, let message = params["message"]?.asString else {
            throw MCPRegistryError.invalidResult("Unsupported MCP input request.")
        }
        let options: [PlanInputOption]
        let text: String
        let url: String?
        let schema: [String: JSONValue]?
        switch params["mode"]?.asString ?? "form" {
        case "form":
            guard let requested = params["requestedSchema"]?.asObject,
                  requested["type"]?.asString == "object", requested["properties"]?.asObject != nil else {
                throw MCPRegistryError.invalidResult("Invalid MCP form schema.")
            }
            schema = requested
            url = nil
            options = [.init(id: "decline", label: "Decline")]
            text = String(message.prefix(4_000)) + "\nEnter the response as a JSON object. Review what will be shared with this server before submitting."
        case "url":
            guard allowURL, let raw = params["url"]?.asString, let components = URLComponents(string: raw),
                  components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil, let validURL = components.url else {
                throw MCPRegistryError.invalidResult("MCP URL elicitation requires a supported chat and a valid HTTPS URL.")
            }
            url = validURL.absoluteString
            schema = nil
            options = [.init(id: "accept", label: "Continue after completing"), .init(id: "decline", label: "Decline")]
            text = "\(String(message.prefix(4_000)))\nThis request opens \(host) in your browser."
        default:
            throw MCPRegistryError.invalidResult("Unsupported MCP elicitation mode.")
        }
        self.request = PlanInputRequest(mode: "mcp", title: "MCP input requested by \(serverID)",
            questions: [.init(id: "response", question: text, options: options, allowCustomAnswer: schema != nil)],
            mcpURL: url, mcpSchema: schema)
    }

    static func wireResponse(_ response: PlanInputResponse, for request: PlanInputRequest) throws -> JSONValue {
        if response.status == .cancelled { return .object(["action": .string("cancel")]) }
        guard let answer = response.answers.first else { throw CoreService.AgentSessionError.invalidPayload }
        if answer.selectedOptionId == "decline" { return .object(["action": .string("decline")]) }
        if request.mcpSchema == nil, answer.selectedOptionId == "accept" {
            return .object(["action": .string("accept")])
        }
        guard let schema = request.mcpSchema, let custom = answer.customAnswer,
              let value = (try? JSONDecoder().decode(JSONValue.self, from: Data(custom.utf8)))?.asObject,
              let properties = schema["properties"]?.asObject,
              (schema["required"]?.asArray ?? []).allSatisfy({ $0.asString.flatMap { value[$0] } != nil }),
              value.allSatisfy({ name, item in properties[name]?.asObject.map { valid(item, for: $0) } == true }) else {
            throw CoreService.AgentSessionError.invalidPayload
        }
        return .object(["action": .string("accept"), "content": .object(value)])
    }

    private static func valid(_ value: JSONValue, for schema: [String: JSONValue]) -> Bool {
        if let options = schema["enum"]?.asArray, !options.contains(value) { return false }
        if let options = schema["oneOf"]?.asArray, !options.contains(where: { $0.asObject?["const"] == value }) { return false }
        if let options = schema["anyOf"]?.asArray, !options.contains(where: { $0.asObject?["const"] == value }) { return false }
        switch (schema["type"]?.asString, value) {
        case ("string", .string(let text)):
            return bound(Double(text.unicodeScalars.count), min: schema["minLength"], max: schema["maxLength"])
        case ("boolean", .bool): return true
        case ("integer", .number(let number)) where number != number.rounded(): return false
        case ("integer", .number(let number)), ("number", .number(let number)):
            return bound(number, min: schema["minimum"], max: schema["maximum"])
        case ("array", .array(let values)):
            guard let items = schema["items"]?.asObject else { return false }
            return bound(Double(values.count), min: schema["minItems"], max: schema["maxItems"])
                && values.enumerated().allSatisfy { index, item in
                    item.asString != nil && valid(item, for: items) && !values.prefix(index).contains(item)
                }
        default: return false
        }
    }

    private static func bound(_ value: Double, min: JSONValue?, max: JSONValue?) -> Bool {
        value >= (min?.asNumber ?? -.infinity) && value <= (max?.asNumber ?? .infinity)
    }
}
