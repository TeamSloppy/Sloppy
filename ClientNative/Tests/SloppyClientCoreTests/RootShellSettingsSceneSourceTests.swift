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
        let sourceText = try source("Sources/SloppyClient/RootShellView.swift")

        #expect(sourceText.contains("let viewModel: RootShellViewModel"))
        #expect(sourceText.contains("init(viewModel: RootShellViewModel"))
        #expect(!sourceText.contains("@State private var viewModel = RootShellViewModel()"))
    }
}
