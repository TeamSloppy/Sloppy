import Foundation
import PluginSDK
import Protocols
#if canImport(CSloppyQuickJS)
import CSloppyQuickJS
#endif

enum CodeMode {
    static let toolID = "tools.execute_js"
    // Turn-control tools depend on being called directly from the model loop.
    static let excludedToolIDs: Set<String> = [toolID, "session.complete", "session.watch",
        "planning.select_route", "planning.request_input", "agent_delegate.finish", "agents.delegate_finish"]
    static let maximumTimeoutMs = 600_000
    static let defaultTimeoutMs = 60_000

    static func enabled(workspaceRoot: URL) -> Bool {
        #if canImport(CSloppyQuickJS)
        let value = ProviderEnvironment.lookup(workspaceRoot: workspaceRoot)("SLOPPY_CODEMODE_ENABLED")
        return ["1", "true", "yes", "on"].contains(value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
        #else
        return false
        #endif
    }

    struct Options: Decodable {
        var maxOutputTokens: Int?
        var timeoutMs: Int?

        enum CodingKeys: String, CodingKey {
            case maxOutputTokens = "max_output_tokens"
            case timeoutMs = "timeout_ms"
        }

        static func parse(_ source: String) throws -> Options {
            guard source.utf8.count <= 64 * 1024, !source.contains("\0") else {
                throw Failure("Script must be at most 64 KiB of JavaScript without literal NUL bytes.")
            }
            let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            let prefix = "// @options:"
            guard !lines.dropFirst().contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) else {
                throw Failure("The @options annotation belongs on the first line.")
            }
            guard let first = lines.first, first.hasPrefix(prefix) else { return Options() }
            let options: Options
            do {
                options = try JSONDecoder().decode(Options.self, from: Data(first.dropFirst(prefix.count).utf8))
            } catch {
                throw Failure("The @options annotation must be a JSON object with integer limits.")
            }
            guard (1...10_000).contains(options.maxOutputTokens ?? 2_000),
                  (1...CodeMode.maximumTimeoutMs).contains(options.timeoutMs ?? CodeMode.defaultTimeoutMs) else {
                throw Failure("max_output_tokens must be 1…10000 and timeout_ms must be 1…600000.")
            }
            return options
        }
    }

    struct Failure: LocalizedError {
        let message: String

        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    typealias Invoke = @Sendable (ToolInvocationRequest) async -> ToolInvocationResult

    struct Request: Decodable, Sendable {
        let id: Int
        let name: String
        let arguments: [String: JSONValue]

        var canRunConcurrently: Bool {
            ToolConcurrencyPolicy.readOnlyToolIDs.contains(name) ||
                (name == "runtime.process" && arguments["action"]?.asString?.lowercased() == "wait")
        }
    }

    struct Completion: Encodable, Sendable {
        let id: Int
        let result: ToolInvocationResult
    }

    struct CapturedOutput: Decodable, Sendable {
        let head: String
        let tail: String?

        func preview(maxBytes: Int) -> (text: String, truncated: Bool) {
            if tail == nil, head.utf8.count <= maxBytes { return (head, false) }
            let marker = "\n…\n"
            let available = maxBytes - marker.utf8.count
            guard available >= 2 else { return (boundedToolText(head, maxBytes: maxBytes), true) }
            let tailSource = (tail ?? head).utf8
            // Reserve most of the preview for late results, which often follow verbose diagnostics.
            let tailBudget = min(tailSource.count, available - available / 5)
            let end = tailSource.suffix(tailBudget).drop(while: { $0 & 0xc0 == 0x80 })
            let start = boundedToolText(head, maxBytes: available - end.count)
            return (start + marker + String(decoding: end, as: UTF8.self), true)
        }
    }

    struct Snapshot: Decodable, Sendable {
        let finished: Bool
        let requests: [Request]
        let error: String?
        let output: CapturedOutput?
        let logs: CapturedOutput?
        let writes: [String: JSONValue]?
    }

    struct ScriptResult {
        let snapshot: Snapshot
        let verificationEvidence: JSONValue?
    }

    #if canImport(CSloppyQuickJS)
    private static let bootstrap = Result {
        guard let url = Bundle.module.url(forResource: "CodeModeBridge", withExtension: "js") else {
            throw Failure("The bundled JavaScript bridge is missing.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func run(
        source: String, options: Options, catalog: [JSONValue], stored: [String: JSONValue],
        invoke: @escaping Invoke
    ) async throws -> ScriptResult {
        let input = JSONValue.object(["catalog": .array(catalog), "stored": .object(stored)])
        let vm = try VM(
            bootstrap: bootstrap.get(), input: encode(input), source: source,
            timeoutMs: options.timeoutMs ?? defaultTimeoutMs
        )
        return try await withThrowingTaskGroup(of: Completion.self) { group in
            defer { group.cancelAll() }
            // Sloppy's approval and process policies still apply independently to every call.
            let allowed = Set(catalog.compactMap { $0.asObject?["name"]?.asString })
            var seen: Set<Int> = []
            var pending: [Request] = []
            var inFlight = 0
            var runningExclusiveCall = false
            var completion: Completion?
            var verificationEvidence: JSONValue?
            while true {
                try Task.checkCancellation()
                let state = try vm.advance(completion)
                try Task.checkCancellation()
                if state.finished {
                    return ScriptResult(snapshot: state, verificationEvidence: verificationEvidence)
                }
                for request in state.requests {
                    guard allowed.contains(request.name), (1...64).contains(request.id),
                          seen.insert(request.id).inserted else {
                        throw Failure("Invalid or unavailable nested tool call.")
                    }
                    pending.append(request)
                }
                while !runningExclusiveCall, inFlight < 8, let next = pending.first {
                    // Preserve the same ordering barriers as the direct model tool batch.
                    if !next.canRunConcurrently && inFlight > 0 { break }
                    let request = pending.removeFirst()
                    runningExclusiveCall = !request.canRunConcurrently
                    inFlight += 1
                    group.addTask {
                        try Task.checkCancellation()
                        let result = await invoke(.init(tool: request.name, arguments: request.arguments))
                        return Completion(id: request.id, result: result)
                    }
                }
                guard let next = try await group.next() else {
                    throw Failure("JavaScript is waiting on a Promise with no pending tool calls.")
                }
                inFlight -= 1
                runningExclusiveCall = false
                verificationEvidence = next.result.data?.asObject?["verificationEvidence"] ?? verificationEvidence
                completion = next
            }
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    // QuickJS is synchronous. A dedicated serial queue confines its C handle and
    // the bridge refreshes its stack base on each entry.
    private final class VM: @unchecked Sendable {
        private let queue = DispatchQueue(label: "sloppy.codemode.quickjs")
        private let handle: OpaquePointer

        init(bootstrap: String, input: String, source: String, timeoutMs: Int) throws {
            handle = try queue.sync {
                guard let vm = sloppy_js_create(Int32(timeoutMs)) else { throw Failure("Could not create QuickJS runtime.") }
                if sloppy_js_start(vm, bootstrap, input, source) < 0 {
                    let error = Failure(String(cString: sloppy_js_error(vm)))
                    sloppy_js_destroy(vm)
                    throw error
                }
                return vm
            }
        }

        deinit {
            queue.sync { sloppy_js_destroy(handle) }
        }

        func advance(_ completion: Completion?) throws -> Snapshot {
            try queue.sync {
                if let completion {
                    guard let ack = sloppy_js_step(handle, try CodeMode.encode(completion)) else { throw failure() }
                    sloppy_js_free_string(ack)
                }
                guard sloppy_js_pump(handle) == 0, let data = sloppy_js_step(handle, "") else { throw failure() }
                defer { sloppy_js_free_string(data) }
                return try JSONDecoder().decode(Snapshot.self, from: Data(String(cString: data).utf8))
            }
        }

        private func failure() -> Failure { Failure(String(cString: sloppy_js_error(handle))) }
    }
    #endif
}
