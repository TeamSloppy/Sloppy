import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Workspace browser")
struct WorkspaceBrowserRuntimeTests {
    @Test func assemblesFragmentedResponsesWithQuotedBracesAndEscapes() throws {
        let source = Data(#"{"id":1,"result":{"text":"quoted } { and \" words","unicode":"привет"}}"#.utf8)
        var buffer = BrowserMessageBuffer()
        var results: [Data] = []
        for byte in source { results += try buffer.append(Data([byte])) }
        #expect(results == [source])
        let together = try buffer.append(Data("{\"id\":2}\n{\"id\":3}".utf8))
        #expect(together.count == 2)
    }
    @Test @MainActor func validatesWebAddresses() throws {
        #expect(try WorkspaceBrowserRuntime.address("example.com").absoluteString == "https://example.com")
        #expect(try WorkspaceBrowserRuntime.address("http://127.0.0.1:25102/browser-test").port == 25102)
        for value in ["file:///C:/Windows", "javascript://alert", "https://user:password@example.com", " "] {
            #expect(throws: (any Error).self) { try WorkspaceBrowserRuntime.address(value) }
        }
    }

    @Test @MainActor func disconnectedCommandsFailImmediately() async {
        let runtime = WorkspaceBrowserRuntime()
        await #expect(throws: (any Error).self) { try await runtime.command("Page.reload") }
        runtime.stop(); runtime.stop()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_BROWSER_INTEGRATION"] == "1"))
    @MainActor func chromiumNavigatesTypesClicksAndCaptures() async throws {
        let runtime = WorkspaceBrowserRuntime()
        defer { runtime.stop() }
        try await runtime.start()
        try await runtime.navigate("http://127.0.0.1:25102/browser-test")
        var ready = false
        for _ in 0..<30 {
            let result = try await runtime.command("Runtime.evaluate", params: ["expression": .string("document.title"), "returnByValue": .bool(true)])
            if result["result"]["value"].string == "Sloppy browser check" { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ready)
        _ = try await runtime.command("Runtime.evaluate", params: ["expression": .string("document.querySelector('#name').focus()")])
        _ = try await runtime.command("Input.insertText", params: ["text": .string("AdaUI test")])
        _ = try await runtime.command("Runtime.evaluate", params: ["expression": .string("document.querySelector('#check').click()")])
        let result = try await runtime.command("Runtime.evaluate", params: ["expression": .string("document.querySelector('#result').textContent"), "returnByValue": .bool(true)])
        #expect(result["result"]["value"].string == "Clicked: AdaUI test")
        let png = try await runtime.screenshot()
        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    }
}
