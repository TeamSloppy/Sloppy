import SwiftUI
import SloppySafariCore
#if os(macOS)
import AppKit
#endif

@main
struct SloppySafariApp: App {
    @StateObject private var store = ConnectionSettingsStore()

    var body: some Scene {
        WindowGroup {
            SettingsView(store: store)
#if os(macOS)
                .background(WindowChromeConfigurator())
#endif
        }
    }
}

#if os(macOS)
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.resizable)
        window.isMovableByWindowBackground = true
    }
}
#endif
