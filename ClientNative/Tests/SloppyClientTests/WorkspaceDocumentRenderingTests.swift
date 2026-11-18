#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Document preview interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceDocumentRenderingTests {
    @Test func markdownAndHTMLSwitchBetweenPreviewAndRaw() async throws {
        for (path, source) in [
            ("/remote/guide.md", "# Document preview\n\nReadable **Markdown**, not an editor.\n\n## Checklist\n\n- Preview opens by default\n- Raw shows the original source\n\n| Mode | Purpose |\n| --- | --- |\n| Preview | Read the document |\n| Raw | Inspect source |\n\n```swift\nlet greeting = \"Hello\"\n```"),
            ("/remote/page.html", "<!doctype html><html><head><style>h1 { color: #6a9a54; } section { border-top: 1px solid #888; padding-top: 16px; }</style></head><body><h1>HTML document</h1><p>Rendered HTML with <strong>formatting</strong> and inline CSS.</p><section>Static, read-only preview.</section><script>document.body.innerHTML = 'UNSAFE SCRIPT RAN';</script><iframe srcdoc='<p>UNSAFE FRAME</p>'></iframe></body></html>")
        ] {
            let fixture = SourceFileFixture(content: source)
            let model = WorkspaceSourceFileViewModel(reference: .init(path: path), apiClient: fixture.api, scope: .project("p"))
            let host = NSHostingView(rootView: WorkspaceSourceFileView(viewModel: model)
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 900, height: 680),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            for _ in 0..<300 {
                if model.content != nil && !model.isLoading { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(model.displayMode == .preview)
            #expect(model.content?.content == source)
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let control = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
            #expect(control.segmentCount == 2)
            #expect(control.selectedSegment == 0)
            if path.hasSuffix("html") {
                let web = try #require(descendants(host).compactMap { $0 as? WKWebView }.first)
                for _ in 0..<200 {
                    if !web.isLoading { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(!web.configuration.websiteDataStore.isPersistent)
                #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
                let text = try await web.evaluateJavaScript("document.body.innerText") as? String
                #expect(text?.contains("HTML document") == true)
                #expect(text?.contains("UNSAFE SCRIPT RAN") == false)
                let image: NSImage? = try await web.takeSnapshot(configuration: nil)
                let tiff = try #require(image?.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                try save(try #require(bitmap.representation(using: .png, properties: [:])), name: "html-document.png")
            }
            try capture(host, name: path.hasSuffix("md") ? "markdown-preview.png" : "html-preview.png")
            control.selectedSegment = 1
            control.sendAction(control.action, to: control.target)
            try await Task.sleep(for: .milliseconds(200))
            #expect(model.displayMode == .raw)
            #expect(descendants(host).compactMap { $0 as? WKWebView }.isEmpty)
            #expect(model.content?.content == source)
            #expect(fixture.requests.count == 1)
            try capture(host, name: path.hasSuffix("md") ? "markdown-raw.png" : "html-raw.png")
            let updated = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
            updated.selectedSegment = 0
            updated.sendAction(updated.action, to: updated.target)
            try await Task.sleep(for: .milliseconds(200))
            #expect(model.displayMode == .preview)
            #expect(fixture.requests.count == 1)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func capture(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try save(try #require(bitmap.representation(using: .png, properties: [:])), name: name)
    }

    private func save(_ data: Data, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_SOURCE_FILE_SCREENSHOTS"] else { return }
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
#endif
