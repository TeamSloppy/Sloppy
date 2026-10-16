import Foundation
import Protocols

/// Structured working state of a session. It lives outside the transcript, so it survives context
/// compaction and is re-inserted into every compacted summary.
public struct SessionWorkLedger: Sendable, Equatable {
    /// Native tools that only read. MCP tools opt in through `data.readOnly` on their result.
    public static let nativeReadOnlyTools: Set<String> = [
        "files.read", "files.grep", "files.list", "memory.search", "memory.recall",
        "project.task_get", "project.task_list", "project.current", "mcp.list_tools", "mcp.list_resources",
    ]
    static let fileMutatingTools: Set<String> = ["files.write", "files.edit"]
    static let planTool = "planning.progress_update"

    struct ReadRecord: Sendable, Equatable {
        var signature: String
        var label: String
        var digest: String
        /// Native file reads go stale when files change; MCP reads do not track the remote state.
        var fileEpoch: Int?
        var served = 0
    }

    public private(set) var goal: String?
    public private(set) var plan: String?
    private(set) var reads: [ReadRecord] = []
    public private(set) var changedFiles: [String] = []
    public private(set) var checks: [String] = []
    private var fileEpoch = 0

    public init() {}

    public var isEmpty: Bool {
        goal == nil && plan == nil && reads.isEmpty && changedFiles.isEmpty && checks.isEmpty
    }

    public mutating func recordGoal(_ text: String) {
        guard goal == nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goal = Self.clip(trimmed, 600)
    }

    static func signature(_ request: ToolInvocationRequest) -> String {
        let args = (try? JSONEncoder.sortedKeys.encode(JSONValue.object(request.arguments)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return request.tool + "|" + args
    }

    /// A short answer for an identical read already performed, or `nil` when the call should run.
    /// The first repeat is answered from the ledger; asking a second time runs the tool for fresh data.
    public mutating func duplicateReadResult(for request: ToolInvocationRequest) -> ToolInvocationResult? {
        let signature = Self.signature(request)
        guard let index = reads.firstIndex(where: { $0.signature == signature }) else { return nil }
        if let epoch = reads[index].fileEpoch, epoch != fileEpoch { return nil }
        guard reads[index].served == 0 else { return nil }
        reads[index].served += 1
        return ToolInvocationResult(
            tool: request.tool,
            ok: true,
            data: .object([
                "alreadyRead": .bool(true),
                "note": .string("This exact call was already made in this session; its content is not repeated. Key facts are below. Move on to implementing; repeat the identical call only if you need fresh data."),
                "digest": .string(reads[index].digest),
            ])
        )
    }

    public mutating func observe(request: ToolInvocationRequest, result: ToolInvocationResult) {
        guard result.ok else { return }
        if request.tool == Self.planTool {
            plan = Self.clip(Self.compactJSON(.object(request.arguments)), 1500)
            return
        }
        if Self.fileMutatingTools.contains(request.tool) {
            fileEpoch += 1
            if let path = request.arguments["path"]?.asString, !changedFiles.contains(path) {
                changedFiles.append(path)
                if changedFiles.count > 40 { changedFiles.removeFirst() }
            }
            return
        }
        if let evidence = result.data?.asObject?["verificationEvidence"]?.asObject {
            let command = evidence["command"]?.asString ?? result.tool
            let kind = evidence["kind"]?.asString ?? "check"
            appendCheck("\(kind): \(Self.clip(command, 100)) → ok [\(evidence["id"]?.asString ?? "-")]")
        }
        let isNativeRead = Self.nativeReadOnlyTools.contains(request.tool)
        let isRemoteRead = result.data?.asObject?["readOnly"]?.asBool == true
        // Commands may change files on disk, so earlier file reads are no longer authoritative.
        if request.tool == "runtime.exec" || request.tool == "runtime.process" { fileEpoch += 1 }
        guard isNativeRead || isRemoteRead else { return }
        let signature = Self.signature(request)
        var record = ReadRecord(
            signature: signature,
            label: Self.label(for: request),
            digest: Self.digest(of: result),
            fileEpoch: isNativeRead ? fileEpoch : nil
        )
        if let index = reads.firstIndex(where: { $0.signature == signature }) {
            record.served = reads[index].fileEpoch == record.fileEpoch ? reads[index].served : 0
            reads[index] = record
        } else {
            reads.append(record)
            if reads.count > 60 { reads.removeFirst() }
        }
    }

    private mutating func appendCheck(_ line: String) {
        checks.append(line)
        if checks.count > 12 { checks.removeFirst() }
    }

    /// Text that is inserted into compacted context. Bounded so it cannot dominate the budget.
    public func render(maxCharacters: Int = 6000) -> String {
        guard !isEmpty else { return "" }
        var lines = ["[Session work ledger — facts gathered before compaction; do not repeat this work]"]
        if let goal { lines.append("Goal: \(goal)") }
        if let plan { lines.append("Current plan/checklist: \(plan)") }
        if !changedFiles.isEmpty { lines.append("Changed files: " + changedFiles.joined(separator: ", ")) }
        if !checks.isEmpty { lines.append("Builds/checks:\n" + checks.map { "- \($0)" }.joined(separator: "\n")) }
        if !reads.isEmpty {
            lines.append("Already read (identical calls are answered from this ledger):")
            lines += reads.map { "- \($0.label): \($0.digest)" }
        }
        let text = lines.joined(separator: "\n")
        return text.count <= maxCharacters ? text : String(text.prefix(maxCharacters)) + "\n…[ledger truncated]"
    }

    static func label(for request: ToolInvocationRequest) -> String {
        if request.tool == "mcp.call_tool" {
            let server = request.arguments["server"]?.asString ?? "?"
            let tool = request.arguments["tool"]?.asString ?? "?"
            let args = request.arguments["arguments"].map { clip(compactJSON($0), 80) } ?? ""
            return "\(server):\(tool) \(args)".trimmingCharacters(in: .whitespaces)
        }
        return request.tool + " " + clip(compactJSON(.object(request.arguments)), 100)
    }

    static func digest(of result: ToolInvocationResult) -> String {
        guard let data = result.data else { return "(no content)" }
        let flattened = compactJSON(data)
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\\"", with: "\"")
        return clip(flattened, 240)
    }

    static func compactJSON(_ value: JSONValue) -> String {
        (try? JSONEncoder.sortedKeys.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}

private extension JSONEncoder {
    static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
