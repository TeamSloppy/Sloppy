#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser agent pointer", .appKitUI, .appKitIsolation)
@MainActor
struct BrowserAgentPointerTests {
    @Test func followsObservedElementAndClearsOnStop() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        runtime.webView.loadHTMLString("<button id='go' onclick='this.textContent=\"Done\"'>Go</button>", baseURL: nil)
        _ = try await runtime.read()
        runtime.agentID = "Yadev"
        runtime.agentPaletteID = "mint"
        _ = try await runtime.click(selector: "#go")
        #expect(runtime.agentPointer.state.point != nil)
        #expect(runtime.agentPointer.state.agentID == "Yadev")
        #expect(try await runtime.read().visibleText == "Done")
        let point = try #require(runtime.agentPointer.state.point)
        #expect((0...1).contains(point.x) && (0...1).contains(point.y))
        #expect(runtime.webView.subviews.last?.hitTest(.zero) == nil)
        runtime.stop()
        #expect(runtime.agentPointer.state.point == nil)
    }

    @Test func rendersExistingPortraitBesideCursor() throws {
        let state = BrowserAgentPointerState()
        state.agentID = "Yadev"
        state.point = CGPoint(x: 0.4, y: 0.4)
        let view = BrowserAgentPointerOverlay(state: state).frame(width: 400, height: 220).background(Color(white: 0.1))
        let image = try #require(ImageRenderer(content: view).nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".artifacts/browser-agent-controls/agent-cursor.png")
        try png.write(to: url)
    }
}
#endif
