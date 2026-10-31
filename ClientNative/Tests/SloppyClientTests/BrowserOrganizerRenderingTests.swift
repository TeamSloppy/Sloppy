#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser organizer rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserOrganizerRenderingTests {
    @Test func noteEditorAutosavesNativeTypingAndChecklistUpdatesTheSameDocument() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserOrganizerRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        let id = state.organizer.createNote()
        let host = NSHostingView(rootView: BrowserNoteEditor(state: state, noteID: id).theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        func textView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable, !text.isFieldEditor { return text }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        let editor = try #require(textView(in: host))
        window.makeFirstResponder(editor)
        let source = "## Before release\n\n- [ ] Ship 🚀\n\n```swift\nlet version = 1\n```"
        editor.insertText(source, replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.organizer.note(id)?.body == source)
        #expect(BrowserOrganizerStore(defaults: defaults).note(id)?.body == source)

        let preview = NSHostingView(rootView: BrowserNotePreview(markdown: source) { line in
            state.organizer.toggleChecklist(noteID: id, line: line)
        }.theme(.sloppyDark).preferredColorScheme(.dark))
        window.contentView = preview
        try await Task.sleep(for: .milliseconds(200))
        let check = try #require(AppKitTestAccessibility.element(in: preview, identifier: "browser-note-check-2"))
        #expect(AppKitTestAccessibility.press(check))
        #expect(state.organizer.note(id)?.body.contains("- [x] Ship 🚀") == true)
    }

    @Test func renderedTaskCompletionUpdatesPersistedTaskAndRemovesItFromActiveList() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserTasksRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        let task = BrowserPersonalTask(title: "Review the launch", dueAt: .now, priority: .high)
        #expect(state.organizer.saveTask(task))
        let host = NSHostingView(rootView: BrowserTasksView(state: state).theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/sloppy-browser-tasks-dark.png"))
        // AppKit table cells host independent SwiftUI accessibility roots.
        func element(in view: NSView, identifier: String) -> NSObject? {
            if let match = AppKitTestAccessibility.element(in: view, identifier: identifier) { return match }
            return view.subviews.lazy.compactMap { element(in: $0, identifier: identifier) }.first
        }
        let toggle = try #require(element(in: host, identifier: "browser-task-toggle-\(task.id)"))
        #expect(AppKitTestAccessibility.press(toggle))
        #expect(state.organizer.tasks.first?.isCompleted == true)
        #expect(BrowserOrganizerStore(defaults: defaults).tasks.first?.isCompleted == true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(element(in: host, identifier: "browser-task-toggle-\(task.id)") == nil)
    }
}
#endif
