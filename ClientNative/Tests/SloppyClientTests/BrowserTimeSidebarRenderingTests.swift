#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser time sidebar", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserTimeSidebarRenderingTests {
    @Test func fullWidthControlsAndHistoryCompletionWorkInTheSidebar() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserTimeSidebar.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        history.record(url: try #require(URL(string: "https://docs.swift.org/concurrency")), title: "Swift guide")
        history.record(url: try #require(URL(string: "https://example.com/article")), title: "Example article")
        let state = BrowserWorkspaceState(defaults: defaults, history: history)
        state.sidebarMode = .time
        let start = Date().addingTimeInterval(-60)
        for second in 0...60 {
            state.time.sample(url: URL(string: "https://example.com"), at: start.addingTimeInterval(Double(second)))
        }
        let host = NSHostingView(rootView: BrowserSidebar(state: state, onLibrary: { _ in }, onSettings: {}, onCollect: { _ in })
            .desktopScreenStyle().theme(.sloppyDark).preferredColorScheme(.dark)
            .environment(\.controlActiveState, .key).environment(\.scenePhase, .active))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 80, width: 340, height: 1000),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle()
        try await snapshot(host, name: "time-sidebar.png")

        let period = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
        #expect(abs(period.bounds.width - (host.bounds.width - 24)) < 4)
        period.selectedSegment = 1
        #expect(period.sendAction(period.action, to: period.target))
        #expect(state.sidebarDrafts.timeWeek)
        period.selectedSegment = 0
        #expect(period.sendAction(period.action, to: period.target))
        #expect(!state.sidebarDrafts.timeWeek)
        let panel = try #require(element(in: host, id: "browser-focus-panel"))
        let panelFrame = try #require(AppKitTestAccessibility.frame(of: panel))
        #expect(abs(panelFrame.width - (host.bounds.width - 24)) < 4)

        let domain = try #require(descendants(host).compactMap { $0 as? NSTextField }
            .first { $0.isEditable && $0.placeholderString == "example.com" })
        domain.scrollToVisible(domain.bounds.insetBy(dx: 0, dy: -90))
        try await settle()
        try await snapshot(host, name: "time-settings.png")
        #expect(window.makeFirstResponder(domain))
        let editor = try #require(domain.currentEditor() as? NSTextView)
        editor.insertText("docs", replacementRange: NSRange(location: 0, length: 0))
        try await settle()
        #expect(state.sidebarDrafts.timeSite == "docs")
        try pressKey("\u{f701}", code: 125, modifiers: [.function, .numericPad], window: window)
        try pressKey("\r", code: 36, window: window)
        try await settle()
        #expect(state.sidebarDrafts.timeSite == "docs.swift.org" || state.time.focusSites.contains("docs.swift.org"))
        if !state.time.focusSites.contains("docs.swift.org") {
            try pressKey("\r", code: 36, window: window)
            try await settle()
        }
        #expect(state.time.focusSites.contains("docs.swift.org"))
        #expect(!state.time.focusSites.contains("docs"))
        #expect(BrowserTimeStore(defaults: defaults).focusSites.contains("docs.swift.org"))
        try await snapshot(host, name: "time-site-added.png")

        window.setContentSize(NSSize(width: 220, height: 1000))
        try await settle()
        #expect(abs(period.bounds.width - (host.bounds.width - 24)) < 4)
        try await snapshot(host, name: "time-sidebar-220.png")
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func element(in view: NSView, id: String) -> NSObject? {
        if view.accessibilityIdentifier() == id { return view }
        if let result = AppKitTestAccessibility.element(in: view, identifier: id) { return result }
        return view.subviews.lazy.compactMap { element(in: $0, id: id) }.first
    }

    private func pressKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(300)) }

    private func snapshot(_ host: NSView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_TIME_SCREENSHOTS"] else { return }
        let destination = URL(fileURLWithPath: directory).appendingPathComponent(name)
        if CGPreflightScreenCaptureAccess(), let window = host.window {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * window.backingScaleFactor)
                configuration.height = Int(window.frame.height * window.backingScaleFactor)
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: destination)
                print("Time sidebar screenshot: compositor")
                return
            }
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: destination)
    }
}
#endif
