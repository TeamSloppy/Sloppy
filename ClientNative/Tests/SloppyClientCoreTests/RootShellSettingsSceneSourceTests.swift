import Foundation
import Testing

@Suite("Root shell settings scene source")
struct RootShellSettingsSceneSourceTests {
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

    @Test("root shell can receive a shared root view model")
    func rootShellCanReceiveSharedRootViewModel() throws {
        let sourceText = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(sourceText.contains("@State var viewModel: RootShellViewModel"))
        #expect(sourceText.contains("init(viewModel: RootShellViewModel"))
        #expect(!sourceText.contains("@State private var viewModel = RootShellViewModel()"))
    }

    @Test("settings are presented as an item-driven full-screen cover")
    func settingsUseFullScreenCover() throws {
        let viewSource = try source("Sources/SloppyClient/Root/RootShellView.swift")
        let viewModelSource = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")
        let destinationSource = try source("Sources/SloppyClientCore/ClientSettingsDestination.swift")

        #expect(viewSource.contains(".fullScreenCover(item: $rootViewModel.presentedSettings)"))
        #expect(viewSource.contains("rootViewModel.presentSettings(destination)"))
        #expect(!viewSource.contains("case .settings(let destination)"))
        #expect(viewModelSource.contains("var presentedSettings: ClientSettingsDestination?"))
        #expect(!viewModelSource.contains("case settings(ClientSettingsDestination)"))
        #expect(destinationSource.contains("Identifiable"))
    }
}
