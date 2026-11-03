#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser notes sidebar", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserNotesSidebarRenderingTests {
    @Test func groupedNotesKeepSearchAndOpenTheirExistingEditor() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserNotesSidebar.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        let now = Date()
        func note(_ title: String, daysAgo: Int, pinned: Bool = false) throws -> UUID {
            let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now))
            let id = state.organizer.createNote(now: date)
            state.organizer.updateNote(id, now: date) {
                $0.title = title; $0.body = "Keep the contents of \(title)."; $0.isPinned = pinned
            }
            return id
        }
        let today = try note("Launch checklist", daysAgo: 0, pinned: true)
        let yesterday = try note("Trip notes", daysAgo: 1)
        let older = try note("API reference", daysAgo: 4)
        state.sidebarMode = .notes
        let host = NSHostingView(rootView: BrowserSidebar(state: state, onLibrary: { _ in }, onSettings: {}, onCollect: { _ in })
            .desktopScreenStyle().theme(.sloppyDark).preferredColorScheme(.dark)
            .environment(\.controlActiveState, .key).environment(\.scenePhase, .active))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 780),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle()
        for id in [today, yesterday, older] {
            #expect(element(in: host, id: "browser-note-\(id)") != nil)
        }
        try await snapshot(host, name: "notes-sidebar.png")

        let search = try #require(fields(in: host).first { $0.placeholderString == "Search notes" })
        #expect(window.makeFirstResponder(search))
        try await settle()
        try await snapshot(host, name: "notes-search-focused.png")
        let editor = try #require(search.currentEditor() as? NSTextView)
        editor.insertText("Launch", replacementRange: NSRange(location: 0, length: 0))
        try await settle()
        #expect(state.sidebarDrafts.noteQuery == "Launch")
        try await snapshot(host, name: "notes-search-filled.png")
        #expect(element(in: host, id: "browser-note-\(today)") != nil)
        #expect(element(in: host, id: "browser-note-\(yesterday)") == nil)
        #expect(element(in: host, id: "browser-note-\(older)") == nil)
        let row = try #require(element(in: host, id: "browser-note-\(today)"))
        #expect(AppKitTestAccessibility.press(row))
        try await settle()
        #expect(state.sidebarDrafts.noteSelection == today)
        #expect(state.organizer.note(today)?.body == "Keep the contents of Launch checklist.")
        #expect(window.sheets.isEmpty)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(250)) }

    private func fields(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
        return own + view.subviews.flatMap { fields(in: $0) }
    }

    private func element(in view: NSView, id: String) -> NSObject? {
        if view.accessibilityIdentifier() == id { return view }
        if let result = AppKitTestAccessibility.element(in: view, identifier: id) { return result }
        return view.subviews.lazy.compactMap { element(in: $0, id: id) }.first
    }

    private func snapshot(_ host: NSView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_NOTES_SCREENSHOTS"] else { return }
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
                return
            }
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
    }
}
#endif
