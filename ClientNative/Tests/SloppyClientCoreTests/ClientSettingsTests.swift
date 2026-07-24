import Foundation
import Testing
@testable import SloppyClientCore

@Suite("ClientSettings")
@MainActor
struct ClientSettingsTests {

    @Test("persists color scheme selection")
    func persistsColorSchemeSelection() {
        UserDefaults.standard.removeObject(forKey: "client_color_scheme")

        let initial = ClientSettings()
        #expect(initial.colorScheme == .dark)

        initial.colorScheme = .dark

        let restored = ClientSettings()
        #expect(restored.colorScheme == .dark)

        UserDefaults.standard.removeObject(forKey: "client_color_scheme")
    }

    @Test("persists chat sidebar mode selection")
    func persistsChatSidebarModeSelection() {
        UserDefaults.standard.removeObject(forKey: "client_chat_sidebar_mode")

        let initial = ClientSettings()
        #expect(initial.chatSidebarMode == .allChats)

        initial.chatSidebarMode = .projects

        let restored = ClientSettings()
        #expect(restored.chatSidebarMode == .projects)

        UserDefaults.standard.removeObject(forKey: "client_chat_sidebar_mode")
    }

    @Test("persists custom project order")
    func persistsCustomProjectOrder() {
        UserDefaults.standard.removeObject(forKey: "client_project_order_ids")

        let initial = ClientSettings()
        #expect(initial.projectOrderIDs.isEmpty)

        initial.projectOrderIDs = ["project-b", "project-a"]

        let restored = ClientSettings()
        #expect(restored.projectOrderIDs == ["project-b", "project-a"])

        UserDefaults.standard.removeObject(forKey: "client_project_order_ids")
    }
}
