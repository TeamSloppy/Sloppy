import Foundation
import Testing

@Suite("Workspace terminal state source")
struct WorkspaceTerminalStateSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("package and main tabs expose SwiftTerm terminal state wiring")
    func packageAndMainTabsExposeSwiftTermTerminalStateWiring() throws {
        let package = try source("Package.swift")
        let mainTabs = try source("Sources/SloppyClient/Navigation/Main/MainTabs.swift")

        #expect(package.contains("https://github.com/migueldeicaza/SwiftTerm"))
        #expect(package.contains(".product(name: \"SwiftTerm\", package: \"SwiftTerm\")"))
        #expect(mainTabs.contains("final class WorkspaceTerminalState"))
        #expect(mainTabs.contains("var isPresented: Bool"))
        #expect(mainTabs.contains("var height: CGFloat"))
        #expect(mainTabs.contains("enum WorkspaceBottomPanelKind"))
        #expect(mainTabs.contains("var selectedPanel: WorkspaceBottomPanelKind"))
        #expect(mainTabs.contains("var sessionID: UUID"))
        #expect(mainTabs.contains("let terminalState: WorkspaceTerminalState"))
    }
}
