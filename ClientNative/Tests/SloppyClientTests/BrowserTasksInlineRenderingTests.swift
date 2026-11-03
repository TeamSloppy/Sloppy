#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser inline tasks", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserTasksInlineRenderingTests {
    @Test func newTaskFocusesAnInlineRowAndEnterCommitsItsTitle() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserInlineTasks.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        let first = BrowserPersonalTask(title: "тест тест тест")
        #expect(state.organizer.saveTask(first))
        #expect(state.organizer.saveTask(.init(title: "тест")))
        state.sidebarMode = .tasks
        let host = NSHostingView(rootView: BrowserSidebar(state: state, onLibrary: { _ in }, onSettings: {}, onCollect: { _ in })
            .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 680),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await settle()
        try snapshot(host, name: "tasks-sidebar.png")

        let search = try #require(editableFields(in: host).first { $0.placeholderString == "Search tasks" })
        let filter = try #require(element(in: host, id: "browser-task-filter"))
        let searchFrame = window.convertToScreen(search.convert(search.bounds, to: nil))
        let filterFrame = try #require(AppKitTestAccessibility.frame(of: filter))
        #expect(abs(searchFrame.midY - filterFrame.midY) < 5)
        #expect(searchFrame.maxX <= filterFrame.minX)
        let toggle = try #require(element(in: host, id: "browser-task-toggle-\(first.id)"))
        let title = try #require(element(in: host, id: "browser-task-edit-\(first.id)"))
        let toggleFrame = try #require(AppKitTestAccessibility.frame(of: toggle))
        let titleFrame = try #require(AppKitTestAccessibility.frame(of: title))
        #expect(abs(toggleFrame.midY - titleFrame.midY) < 3)
        try snapshot(host, name: "tasks-sidebar.png")

        let newTask = try #require(element(in: host, id: "browser-task-new"))
        #expect(AppKitTestAccessibility.press(newTask))
        try await settle()
        let draftID = try #require(state.sidebarDrafts.newTask?.id)
        #expect(state.organizer.tasks.count == 2)
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        #expect(editableFields(in: host).contains { $0.placeholderString == "Task title" && $0.currentEditor() === editor })
        editor.insertText("  A new task  ", replacementRange: NSRange(location: 0, length: 0))
        try await settle()
        #expect(state.sidebarDrafts.newTask?.title == "  A new task  ")
        try snapshot(host, name: "tasks-inline-editing.png")
        try pressKey("\r", code: 36, window: window)
        try await settle()
        #expect(state.sidebarDrafts.newTask == nil)
        #expect(state.organizer.tasks.first { $0.id == draftID }?.title == "A new task")
        #expect(BrowserOrganizerStore(defaults: defaults).tasks.first { $0.id == draftID }?.title == "A new task")
        #expect(element(in: host, id: "browser-task-inline-title") == nil)
        #expect(element(in: host, id: "browser-task-edit-\(draftID)") != nil)
        #expect(window.sheets.isEmpty)
        try snapshot(host, name: "tasks-inline-saved.png")

        #expect(AppKitTestAccessibility.press(newTask))
        try await settle()
        try pressKey("\r", code: 36, window: window)
        try await settle()
        #expect(state.organizer.tasks.count == 3)
        #expect(state.sidebarDrafts.newTask == nil)
        #expect(AppKitTestAccessibility.press(newTask))
        try await settle()
        try pressKey("\u{1b}", code: 53, window: window)
        try await settle()
        #expect(state.sidebarDrafts.newTask == nil)
        #expect(state.organizer.tasks.count == 3)

        for width in [220.0, 360.0] {
            window.setContentSize(NSSize(width: width, height: 680))
            try await settle()
            let filter = try #require(element(in: host, id: "browser-task-filter"))
            let frame = try #require(AppKitTestAccessibility.frame(of: filter))
            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
            #expect(frame.maxX <= bounds.maxX)
            try snapshot(host, name: "tasks-sidebar-\(Int(width)).png")
        }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }

    private func element(in view: NSView, id: String) -> NSObject? {
        if view.accessibilityIdentifier() == id { return view }
        if let match = AppKitTestAccessibility.element(in: view, identifier: id) { return match }
        return view.subviews.lazy.compactMap { element(in: $0, id: id) }.first
    }

    private func editableFields(in view: NSView) -> [NSTextField] {
        let fields = (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
        return fields + view.subviews.flatMap { editableFields(in: $0) }
    }

    private func pressKey(_ characters: String, code: UInt16, window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }

    private func snapshot(_ host: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_TASK_SCREENSHOTS"] else { return }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
#endif
