import Foundation
import Testing

@Suite("Chat toolbar ownership")
struct ChatToolbarOwnershipSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("macOS composer owns model selection while other platforms retain toolbar fallback")
    func composerOwnsMacModelSelection() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreen.swift")
        let composer = try source("Sources/SloppyFeatureChat/Screens/Chat/Views/ChatComposerView.swift")

        #expect(mainView.contains("#if !os(macOS)"))
        #expect(mainView.contains("ChatContextToolbarMenu("))
        #expect(mainView.contains("showsContextToolbar: false"))
        #expect(chatScreen.contains("#if os(macOS)\n        content"))
        #expect(chatScreen.contains("ChatContextToolbarModifier"))
        #expect(composer.contains("ComposerOptionsMenuView("))
        #expect(composer.contains("chat.composer.model-picker"))
    }
}
