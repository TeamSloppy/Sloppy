import Foundation
import Testing
@testable import SloppyClientCore

struct ToolApprovalPresentationTests {
    @Test("pending approvals retain the complete server payload")
    func decodingRetainsArgumentsAndGrants() throws {
        let payload = Data(#"""
        {
          "id":"approval", "status":"pending", "tool":"runtime.exec", "updatedAt":"2026-11-02T00:00:00Z",
          "arguments":{"command":"/bin/bash","arguments":["-lc","printf 'hello'\necho done"],"cwd":"/work/my project","timeoutMs":60000,"other":{"enabled":true,"value":null}},
          "grants":[{"kind":"directory","tool":"runtime.exec","operation":"exec","resource":"/work/my project"}]
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let approval = try decoder.decode(PendingToolApprovalRecord.self, from: payload)
        #expect(approval.arguments?["cwd"] == .string("/work/my project"))
        #expect(approval.arguments?["timeoutMs"] == .number(60000))
        #expect(approval.arguments?["other"] == .object(["enabled": .bool(true), "value": .null]))
        #expect(approval.grants?.first?.resource == "/work/my project")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #expect(try decoder.decode(PendingToolApprovalRecord.self, from: encoder.encode(approval)) == approval)
        let display = ToolApprovalPresentation(approval: approval)
        #expect(display.commandLine?.contains("printf '\\''hello'\\''\necho done") == true)
        #expect(display.workingDirectory == "/work/my project")
        #expect(display.accessDetails == ["exec: /work/my project"])
        #expect(display.scopeDetail == "Session and Always remember the access shown above.")
    }

    @Test("argv display preserves empty arguments, quoting, and shell metacharacters")
    func exactArgv() {
        let record = approval(tool: "runtime.exec", arguments: [
            "command": .string("/bin/echo"),
            "arguments": .array([.string(""), .string("two words"), .string("it's"), .string("$HOME; echo danger")]),
        ])
        let display = ToolApprovalPresentation(approval: record)
        #expect(display.commandLine == "/bin/echo '' 'two words' 'it'\\''s' '$HOME; echo danger'")
        #expect(display.workingDirectory == "Session default")
        #expect(display.scopeDetail.contains("other calls to runtime.exec"))
    }

    @Test("the reason cannot replace or summarize away the actual script")
    func completeMultilineScript() {
        let script = (0..<100).map { "echo line-\($0)" }.joined(separator: "\n") + "\necho SCRIPT_END"
        var record = approval(tool: "runtime.exec", arguments: [
            "command": .string("/bin/bash"), "arguments": .array([.string("-lc"), .string(script)]),
        ])
        record.reason = "Just a quick inspection"
        let display = ToolApprovalPresentation(approval: record)
        #expect(display.content == "/bin/bash -lc '\(script)'")
        #expect(display.content.hasSuffix("echo SCRIPT_END'"))
        #expect(!display.content.contains(record.reason ?? ""))
    }

    @Test("other tools and malformed argv retain all raw parameters")
    func rawParameterFallback() throws {
        let arguments: [String: ToolApprovalArgumentValue] = [
            "path": .string("/work/日本語 notes.md"), "values": .array([.number(2), .bool(false), .null]),
        ]
        let display = ToolApprovalPresentation(approval: approval(tool: "files.write", arguments: arguments))
        #expect(display.commandLine == nil)
        #expect(display.title == "Parameters")
        #expect(try JSONDecoder().decode([String: ToolApprovalArgumentValue].self,
                                      from: Data(display.content.utf8)) == arguments)
        let malformed = ToolApprovalPresentation(approval: approval(tool: "runtime.exec", arguments: [
            "command": .string("/bin/echo"), "arguments": .array([.string("visible"), .number(1)]),
        ]))
        #expect(malformed.commandLine == nil)
        #expect(malformed.content.contains("visible"))
        #expect(malformed.content.contains("1"))
    }

    @Test("older records without parameters remain decodable and say details are unavailable")
    func legacyApproval() throws {
        let data = Data(#"{"id":"old","status":"pending","updatedAt":0}"#.utf8)
        let old = try JSONDecoder().decode(PendingToolApprovalRecord.self, from: data)
        #expect(old.arguments == nil)
        #expect(old.grants == nil)
        #expect(ToolApprovalPresentation(approval: old).content == "Arguments are not available for this request.")
    }

    private func approval(tool: String, arguments: [String: ToolApprovalArgumentValue]) -> PendingToolApprovalRecord {
        .init(id: "approval", status: "pending", tool: tool, arguments: arguments, updatedAt: Date())
    }
}
