import SwiftUI
import SafariExtensionCore

@main
struct SafariExtensionApp: App {
    @StateObject private var store = ConnectionSettingsStore()

    var body: some Scene {
        WindowGroup {
            SettingsView(store: store)
        }
    }
}
