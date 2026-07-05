import Foundation
import Testing

@Suite("Desktop tab strip split source")
struct DesktopWorkspaceTabStripSplitSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("desktop tab strip wires drag and drop into split creation")
    func desktopTabStripWiresDragAndDropIntoSplitCreation() throws {
        let source = try source("Sources", "SloppyClient", "DesktopWorkspaceTabStrip.swift")

        #expect(source.contains(".draggable(tab.id.uuidString)"))
        #expect(source.contains(".dropDestination(for: String.self)"))
        #expect(source.contains("viewModel.beginDesktopSplit(source: sourceTabID, target: tab.id)"))
    }

    @Test("desktop tab strip blocks window background dragging while reordering tabs")
    func desktopTabStripBlocksWindowBackgroundDragging() throws {
        let source = try source("Sources", "SloppyClient", "DesktopWorkspaceTabStrip.swift")

        #expect(source.contains("WindowDragGestureShield {"))
        #expect(source.contains("override var mouseDownCanMoveWindow: Bool { false }"))
        #expect(source.contains("hostingView.autoresizingMask = [.width, .height]"))
        #expect(!source.contains("NSLayoutConstraint.activate(["))
    }
}
