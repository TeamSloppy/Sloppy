import AnyLanguageModel
import Foundation
import Protocols

struct DebugReadLogsTool: CoreTool {
    let domain = "debug"
    let title = "Read debug logs"
    let status = "fully_functional"
    let name = "debug.read_logs"
    let description = "Read and summarize agent debug NDJSON logs from a workspace file."

    private static let defaultRecentLimit = 50

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "path", description: "Path to the NDJSON debug log file", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "sessionId", description: "Optional session id to filter log entries", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "maxBytes", description: "Maximum bytes to read", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let pathValue = arguments["path"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pathValue.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`path` is required.", retryable: false)
        }
        guard let fileURL = context.resolveReadablePath(pathValue) else {
            return toolFailure(tool: name, code: "path_not_allowed", message: "Log file path is outside allowed roots.", retryable: false)
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            let detail = FileSystemToolErrorMapping.describePathIsDirectory(operation: .read, path: fileURL.path)
            return toolFailure(tool: name, code: detail.code, message: detail.message, retryable: detail.retryable, hint: detail.hint)
        }
        guard exists else {
            let detail = FileSystemToolErrorMapping.describeMissingPath(operation: .read, path: fileURL.path)
            return toolFailure(tool: name, code: detail.code, message: detail.message, retryable: detail.retryable, hint: detail.hint)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let maxBytes = arguments["maxBytes"]?.asInt ?? context.policy.guardrails.maxReadBytes
            if data.count > max(1, maxBytes) {
                return toolFailure(tool: name, code: "file_too_large", message: "Log file exceeds max readable bytes.", retryable: false)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return toolFailure(tool: name, code: "binary_not_supported", message: "Only UTF-8 log files are supported.", retryable: false)
            }
            let sessionID = arguments["sessionId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = summarize(text: text, path: fileURL.path, sizeBytes: data.count, sessionID: sessionID?.isEmpty == false ? sessionID : nil)
            return toolSuccess(tool: name, data: summary)
        } catch {
            let detail = FileSystemToolErrorMapping.describe(error: error, operation: .read, path: fileURL.path)
            return toolFailure(tool: name, code: detail.code, message: detail.message, retryable: detail.retryable, hint: detail.hint)
        }
    }

    private func summarize(text: String, path: String, sizeBytes: Int, sessionID: String?) -> JSONValue {
        var entries: [DebugLogEntry] = []
        var parseErrors: [JSONValue] = []
        var physicalLineCount = 0

        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            physicalLineCount += 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            do {
                let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
                guard let object = value.asObject else {
                    parseErrors.append(.object([
                        "line": .number(Double(offset + 1)),
                        "message": .string("Expected a JSON object."),
                    ]))
                    continue
                }
                if let sessionID, object["sessionId"]?.asString != sessionID {
                    continue
                }
                entries.append(DebugLogEntry(line: offset + 1, object: object))
            } catch {
                parseErrors.append(.object([
                    "line": .number(Double(offset + 1)),
                    "message": .string(error.localizedDescription),
                ]))
            }
        }

        let grouped = Dictionary(grouping: entries) { entry in
            GroupKey(
                hypothesisId: entry.hypothesisId,
                location: entry.location,
                message: entry.message
            )
        }
        let groups = grouped.map { key, values in
            groupPayload(key: key, entries: values)
        }.sorted { lhs, rhs in
            let leftCount = lhs.asObject?["count"]?.asNumber ?? 0
            let rightCount = rhs.asObject?["count"]?.asNumber ?? 0
            if leftCount != rightCount {
                return leftCount > rightCount
            }
            let leftKey = lhs.asObject?["key"]?.asString ?? ""
            let rightKey = rhs.asObject?["key"]?.asString ?? ""
            return leftKey < rightKey
        }

        let recentEntries = entries.suffix(Self.defaultRecentLimit).map(entryPayload)

        var payload: [String: JSONValue] = [
            "path": .string(path),
            "sizeBytes": .number(Double(sizeBytes)),
            "lineCount": .number(Double(physicalLineCount)),
            "entryCount": .number(Double(entries.count)),
            "parseErrorCount": .number(Double(parseErrors.count)),
            "parseErrors": .array(parseErrors),
            "groups": .array(groups),
            "recentEntries": .array(recentEntries),
            "timingSummary": timingPayload(entries.compactMap(\.elapsedMs)),
        ]
        if let sessionID {
            payload["sessionId"] = .string(sessionID)
        }
        if let first = entries.compactMap(\.timestamp).min() {
            payload["firstTimestamp"] = .number(first)
        }
        if let last = entries.compactMap(\.timestamp).max() {
            payload["lastTimestamp"] = .number(last)
        }
        return .object(payload)
    }

    private func groupPayload(key: GroupKey, entries: [DebugLogEntry]) -> JSONValue {
        var payload: [String: JSONValue] = [
            "key": .string(key.key),
            "hypothesisId": .string(key.hypothesisId),
            "location": .string(key.location),
            "message": .string(key.message),
            "count": .number(Double(entries.count)),
            "timingSummary": timingPayload(entries.compactMap(\.elapsedMs)),
        ]
        if let first = entries.compactMap(\.timestamp).min() {
            payload["firstTimestamp"] = .number(first)
        }
        if let last = entries.compactMap(\.timestamp).max() {
            payload["lastTimestamp"] = .number(last)
        }
        return .object(payload)
    }

    private func entryPayload(_ entry: DebugLogEntry) -> JSONValue {
        var object = entry.object
        object["line"] = .number(Double(entry.line))
        return .object(object)
    }

    private func timingPayload(_ values: [Double]) -> JSONValue {
        guard !values.isEmpty else {
            return .object(["count": .number(0)])
        }
        let total = values.reduce(0, +)
        return .object([
            "count": .number(Double(values.count)),
            "min": .number(values.min() ?? 0),
            "max": .number(values.max() ?? 0),
            "avg": .number(total / Double(values.count)),
        ])
    }
}

private struct DebugLogEntry {
    let line: Int
    let object: [String: JSONValue]

    var hypothesisId: String {
        object["hypothesisId"]?.asString ?? "(missing)"
    }

    var location: String {
        object["location"]?.asString ?? "(missing)"
    }

    var message: String {
        object["message"]?.asString ?? "(missing)"
    }

    var timestamp: Double? {
        object["timestamp"]?.asNumber
    }

    var elapsedMs: Double? {
        object["data"]?.asObject?["elapsedMs"]?.asNumber
    }
}

private struct GroupKey: Hashable {
    let hypothesisId: String
    let location: String
    let message: String

    var key: String {
        "\(hypothesisId)|\(location)|\(message)"
    }
}
