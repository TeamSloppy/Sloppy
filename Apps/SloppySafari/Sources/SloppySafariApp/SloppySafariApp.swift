import SwiftUI
import SloppySafariCore

@main
struct SloppySafariApp: App {
    @StateObject private var store = ConnectionSettingsStore()

    var body: some Scene {
        WindowGroup {
            SettingsView(store: store)
        }
    }
}
