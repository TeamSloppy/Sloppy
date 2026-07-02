import Foundation
import Testing

@Suite("Mobile workspace tabs source")
struct MobileWorkspaceTabsSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("main view presents mobile overview from detail container")
    func mainViewPresentsMobileOverviewFromDetailContainer() throws {
        let mainView = try source("Sources/SloppyClient/MainView.swift")
        let overview = try source("Sources/SloppyClient/MobileWorkspaceTabsOverview.swift")

        #expect(mainView.contains("MobileWorkspaceTabsOverview("))
        #expect(mainView.contains("viewModel.isMobileTabsOverviewPresented"))
        #expect(overview.contains("struct MobileWorkspaceTabsOverview: View"))
        #expect(overview.contains("ForEach(tabs)"))
    }
}
