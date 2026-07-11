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

    @Test("mounted chat tabs delegate context toolbar ownership to main view")
    func mountedTabsDoNotRegisterDuplicateToolbarItems() throws {
        let mainView = try source("Sources/SloppyClient/Navigation/Main/MainView.swift")
        let chatScreen = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreen.swift")

        #expect(mainView.contains("ToolbarItem(id: \"active-chat-agent\""))
        #expect(mainView.contains("ToolbarItem(id: \"active-chat-model\""))
        #expect(mainView.contains("showsContextToolbar: false"))
        #expect(chatScreen.contains("ChatContextToolbarModifier"))
    }
}
