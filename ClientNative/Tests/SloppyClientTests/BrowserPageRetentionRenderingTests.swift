#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser page retention WebKit", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserPageRetentionRenderingTests {
    private func fixture(html: String? = nil, _ run: @MainActor (BrowserWorkspaceState, BrowserRetentionTestClock, URL) async throws -> Void) async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserRetentionWebKit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture(html: html)
        let url = try await server.start()
        let clock = BrowserRetentionTestClock()
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults), retentionClock: { clock.now }, startsPageMaintenance: false)
        try server.allowHTTP(in: state)
        let host = NSHostingView(rootView: BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        try await run(state, clock, url)
    }

    private func load(_ url: URL, in state: BrowserWorkspaceState) async throws -> UUID {
        state.open(url, inNewTab: true)
        let id = try #require(state.selectedID)
        try await waitForPage(try #require(state.selectedPage))
        return id
    }

    private func waitForPage(_ page: WorkspaceWebViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while page.isLoading || page.currentURL == nil || page.nativeWebView == nil || page.nativeWebView?.isLoading == true {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func cleanPageReleasesWebKitAndRestoresNavigationWithoutDroppingTheTab() async throws {
        try await fixture(html: "<!doctype html><title>Retention</title><body style='min-height:5000px'><input id='name'></body>") { state, clock, url in
            let first = try await load(url, in: state)
            let original = try #require(state.pages[first])
            _ = try await original.ensureBrowserRuntime().open(url: url.appendingPathComponent("next").absoluteString)
            #expect(original.nativeWebView?.canGoBack == true)
            _ = try await original.nativeWebView?.evaluateJavaScript("window.scrollTo(0,500); true;")
            try await Task.sleep(for: .milliseconds(100))
            weak var releasedView = original.nativeWebView
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            #expect(original.presentations == 0)
            let count = await state.discardInactivePages()
            #expect(count == 1)
            #expect(state.tabs.count == 2)
            #expect(state.pages[first] == nil)
            #expect(original.nativeWebView == nil)
            #expect(original.browserRuntime == nil)
            #expect(state.tabs.first { $0.id == first }?.interactionState != nil)
            for _ in 0..<50 where releasedView != nil { try await Task.sleep(for: .milliseconds(10)) }
            #expect(releasedView == nil)
            state.select(first)
            let restored = try #require(state.selectedPage)
            try await waitForPage(restored)
            #expect(restored !== original)
            #expect(restored.currentURL?.path == "/next")
            #expect(restored.nativeWebView?.canGoBack == true)
            let restoredY = try await restored.nativeWebView?.evaluateJavaScript("window.scrollY") as? Double
            #expect((restoredY ?? 0) >= 450)
        }
    }

    @Test func editsInMainDocumentAndNestedFramesPreventDiscard() async throws {
        try await fixture { state, clock, url in
            let first = try await load(url, in: state)
            let page = try #require(state.pages[first])
            let view = try #require(page.nativeWebView)
            _ = try await view.evaluateJavaScript("document.querySelector('#name').value='Unsaved draft'; document.querySelector('#name').dispatchEvent(new Event('input', {bubbles:true}));")
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 0)
            #expect(state.pages[first] === page)
            state.select(first)
            let cleanURL = url.appendingPathComponent("clean-after-edits")
            _ = try await page.ensureBrowserRuntime().open(url: cleanURL.absoluteString)
            for _ in 0..<100 {
                if view.url == cleanURL, !view.isLoading { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(view.url == cleanURL && !view.isLoading)
            try await Task.sleep(for: .milliseconds(100))
            _ = try await view.callAsyncJavaScript("const frame=document.createElement('iframe'); frame.src=source; document.body.append(frame); return true;",
                arguments: ["source": url.appendingPathComponent("embedded").absoluteString], in: nil, contentWorld: .page)
            var frameReady = false
            for _ in 0..<40 {
                frameReady = try await view.evaluateJavaScript("Boolean(document.querySelector('iframe')?.contentDocument?.querySelector('input'))") as? Bool == true
                if frameReady { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(frameReady)
            #expect(await page.browserRuntime?.activity.inspect() == true)
            _ = try await view.evaluateJavaScript("const input=document.querySelector('iframe').contentDocument.querySelector('input'); input.value='Nested draft'; input.dispatchEvent(new Event('input', {bubbles:true}));")
            state.select(try #require(state.tabs.last?.id))
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 0)
            #expect(state.pages[first] === page)
        }
    }

    @Test func webRTCAndAgentOperationsPreventDiscard() async throws {
        try await fixture { state, clock, url in
            let first = try await load(url, in: state)
            let page = try #require(state.pages[first])
            let view = try #require(page.nativeWebView)
            _ = try await view.evaluateJavaScript("window.retentionPeer = new RTCPeerConnection(); true;")
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 0)
            _ = try await view.evaluateJavaScript("window.retentionPeer.close();")
            try await Task.sleep(for: .milliseconds(100))
            page.beginAutomation()
            #expect(await state.discardInactivePages() == 0)
            page.endAutomation()
            #expect(await state.discardInactivePages() == 1)
        }
    }

    @Test func unknownFrameStateAndPageBecomingVisibleDuringProbeStayResident() async throws {
        try await fixture { state, clock, url in
            let first = try await load(url, in: state)
            let page = try #require(state.pages[first])
            let view = try #require(page.nativeWebView)
            _ = try await view.evaluateJavaScript("const frame=document.createElement('iframe'); frame.srcdoc='<p>Frame</p>'; document.body.append(frame);")
            try await Task.sleep(for: .milliseconds(200))
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            // A frame which never answers must not be mistaken for an empty page.
            _ = try await view.evaluateJavaScript("globalThis.__sloppyPageRetention.probe = () => {}; true;", in: nil, contentWorld: BrowserPageActivityMonitor.world)
            let sweep = Task { await state.discardInactivePages() }
            try await Task.sleep(for: .milliseconds(50))
            state.select(first)
            #expect(await sweep.value == 0)
            #expect(state.pages[first] === page)
            #expect(state.selectedID == first)
        }
    }

    @Test func cleanCrossOriginFrameCanBeDiscarded() async throws {
        try await fixture { state, clock, url in
            let first = try await load(url, in: state)
            let page = try #require(state.pages[first])
            let view = try #require(page.nativeWebView)
            var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            components.host = "localhost"
            let child = try #require(components.url)
            _ = try await view.callAsyncJavaScript("globalThis.frameReady=false; const frame=document.createElement('iframe'); frame.onload=()=>{globalThis.frameReady=true;}; frame.src=source; document.body.append(frame); return true;",
                arguments: ["source": child.absoluteString], in: nil, contentWorld: .page)
            var ready = false
            for _ in 0..<60 {
                ready = try await view.evaluateJavaScript("globalThis.frameReady === true") as? Bool == true
                if ready { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(ready)
            #expect(await page.browserRuntime?.activity.inspect() == true)
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            #expect(await state.discardInactivePages() == 1)
        }
    }

    @Test func playingMediaIsProtectedAndPausingAllowsDiscard() async throws {
        try await fixture { _, _, url in
            let configuration = WKWebViewConfiguration()
            configuration.mediaTypesRequiringUserActionForPlayback = []
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: configuration)
            let runtime = WorkspaceBrowserToolRuntime(webView: view)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            _ = try await runtime.open(url: url.absoluteString)
            var wave = Data("RIFF".utf8)
            func append32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) } }
            append32(8036)
            wave.append(Data("WAVEfmt ".utf8)); append32(16)
            wave.append(contentsOf: [1, 0, 1, 0]); append32(8000); append32(8000)
            wave.append(contentsOf: [1, 0, 8, 0]); wave.append(Data("data".utf8)); append32(8000)
            wave.append(Data(repeating: 128, count: 8000))
            _ = try await view.callAsyncJavaScript("const audio=document.createElement('audio'); audio.id='retentionAudio'; audio.muted=true; audio.loop=true; audio.src=source; document.body.append(audio); await Promise.race([audio.play(), new Promise((_,reject)=>setTimeout(()=>reject(new Error('play timeout')),3000))]); return true;",
                arguments: ["source": "data:audio/wav;base64," + wave.base64EncodedString()], in: nil, contentWorld: .page)
            #expect(await runtime.safeToDiscard(at: .now.addingTimeInterval(3601)) == false)
            #expect(runtime.activity.lastFailure == .media)
            _ = try await view.evaluateJavaScript("document.querySelector('#retentionAudio').pause(); true;")
            #expect(await runtime.safeToDiscard(at: .now.addingTimeInterval(3601)))
        }
    }

    @Test func anInFlightAgentOperationAndItsPossibleEditsStayResident() async throws {
        try await fixture { state, clock, url in
            let first = try await load(url, in: state)
            let page = try #require(state.pages[first])
            let runtime = page.ensureBrowserRuntime()
            _ = try await load(url.appendingPathComponent("other"), in: state)
            clock.advance(3601)
            let operation = Task { try await runtime.evaluate(expression: "new Promise(resolve => setTimeout(() => resolve(42), 250))") }
            try await Task.sleep(for: .milliseconds(50))
            #expect(runtime.activeOperations > 0)
            #expect(await state.discardInactivePages() == 0)
            _ = try await operation.value
            #expect(await state.discardInactivePages() == 0)
            #expect(state.pages[first] === page)
        }
    }
}
#endif
