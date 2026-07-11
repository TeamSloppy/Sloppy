import Foundation
import Testing

@Suite("Workspace terminal mac host source")
struct WorkspaceTerminalMacHostSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("terminal runtime defines a hosting protocol")
    func terminalRuntimeDefinesAHostingProtocol() throws {
        let runtime = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalHosting.swift")

        #expect(runtime.contains("protocol WorkspaceTerminalHosting"))
        #expect(runtime.contains("func focus()"))
    }

    @Test("mac host uses SwiftTerm local process terminal view")
    func macHostUsesSwiftTermLocalProcessTerminalView() throws {
        let host = try source("Sources", "SloppyClient", "Workspace", "Terminal", "WorkspaceTerminalMacHostView.swift")
        let viewModel = try source("Sources", "SloppyClient", "Navigation", "Main", "MainViewModel.swift")
        let mainView = try source("Sources", "SloppyClient", "Navigation", "Main", "MainView.swift")

        #expect(host.contains("#if os(macOS)"))
        #expect(host.contains("import SwiftTerm"))
        #expect(host.contains("LocalProcessTerminalView"))
        #expect(host.contains("currentDirectory: session.workingDirectory.path"))
        #expect(viewModel.contains("func makeTerminalHostView(for tabID: WorkspaceTab.ID) -> AnyView"))
        #expect(mainView.contains("viewModel.makeTerminalHostView(for: selectedTabID)"))
    }
}
