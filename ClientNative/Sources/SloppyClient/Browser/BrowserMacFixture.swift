#if DEBUG && os(macOS)
import SwiftUI
import SloppyClientUI

/// Launches the production Browse surface without a Core login or personal tabs.
@MainActor
struct BrowserMacFixture: View {
    @State private var state = BrowserWorkspaceState(defaults: UserDefaults(suiteName: "team.sloppy.browser.qa") ?? .standard)
    @State private var started = false

    var body: some View {
        BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in })
            .frame(minWidth: 1120, minHeight: 760)
            .task {
                guard !started else { return }
                started = true
                await state.extensions.restore()
                if let address = argument("--browser-fixture-url="), let url = URL(string: address) {
                    state.open(url, inNewTab: true)
                }
                if let path = argument("--browser-fixture-extension=") {
                    do { try await state.extensions.importExtensions(at: URL(fileURLWithPath: path)) }
                    catch { state.extensions.lastError = error.localizedDescription }
                }
            }
    }

    private func argument(_ prefix: String) -> String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}
#endif
