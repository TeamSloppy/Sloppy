#if os(macOS)
import SwiftUI

@MainActor
struct BrowserExtensionsMenu: View {
    let state: BrowserWorkspaceState
    @State private var showsManager = false

    var body: some View {
        Menu {
            ForEach(state.extensions.records.filter(\.enabled)) { record in
                Button(record.name) { state.extensionBridge?.performAction(record.id) }
                if let context = state.extensions.contexts[record.id], context.optionsPageURL != nil {
                    Button("\(record.name) settings…") {
                        Task {
                            do { try await state.extensionBridge?.webExtensionController(state.extensions.controller, openOptionsPageFor: context) }
                            catch { state.extensions.lastError = error.localizedDescription; showsManager = true }
                        }
                    }
                }
            }
            Divider()
            Button("Manage Web Extensions…") { showsManager = true }
        } label: {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 13))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Web Extensions")
        .accessibilityIdentifier("browser-extensions-menu")
        .help("Web Extensions")
        .sheet(isPresented: $showsManager) { BrowserExtensionsSheet(extensions: state.extensions) }
    }
}
#endif
