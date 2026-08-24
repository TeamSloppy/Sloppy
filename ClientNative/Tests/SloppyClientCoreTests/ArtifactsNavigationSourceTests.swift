import Foundation
import Testing

@Suite("Artifacts navigation source")
struct ArtifactsNavigationSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("macOS sidebar replaces search chats with artifacts")
    func macOSSidebarReplacesSearchChatsWithArtifacts() throws {
        let sidebar = try source(
            "Sources/SloppyClient/Navigation/Platforms/macOS/MacMainSidebar.swift"
        )

        #expect(!sidebar.contains("title: \"Search chats\""))
        #expect(sidebar.contains("title: \"Artifacts\""))
        #expect(sidebar.contains("action: viewModel.selectArtifacts"))
    }

    @Test("artifacts screen uses English interface copy")
    func artifactsScreenUsesEnglishInterfaceCopy() throws {
        let screen = try source("Sources/SloppyClient/ArtifactLibrary/ArtifactsScreen.swift")

        #expect(screen.contains("Search artifacts"))
        #expect(screen.contains("No artifacts yet"))
        #expect(screen.contains("Open source chat"))
        #expect(!screen.contains("Артефакт"))
    }

    @Test("artifacts list keeps the shared chat background visible")
    func artifactsListUsesTransparentBackground() throws {
        let screen = try source("Sources/SloppyClient/ArtifactLibrary/ArtifactsScreen.swift")

        #expect(!screen.contains(".background(theme.colors.background)"))
        #expect(screen.contains(".scrollContentBackground(.hidden)"))
        #expect(screen.contains(".listRowBackground(Color.clear)"))
    }

    @Test("main navigation presents the artifacts list")
    func mainNavigationPresentsArtifactsList() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let mainViewModel = try source("Sources/SloppyClient/Navigation/Main/MainViewModel.swift")

        #expect(mainView.contains("viewModel.selectedAppSection == .artifacts"))
        #expect(mainView.contains("ArtifactsScreen("))
        #expect(mainViewModel.contains("func selectArtifacts()"))
    }
}
