import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
struct BrowserTimeTracking: ViewModifier {
    let state: BrowserWorkspaceState
    var isCovered = false
    @Environment(\.scenePhase) private var scenePhase

    private func sample() {
        var active = scenePhase == .active && !isCovered
#if os(macOS)
        active = active && NSApp.isActive && state.selectedPage?.nativeWebView?.window?.isKeyWindow == true
#endif
        state.setTimeTrackingActive(active)
    }

    func body(content: Content) -> some View {
        content
            .task {
                state.setWorkspacePresented(true)
                sample()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                    sample()
                }
            }
            .onChange(of: scenePhase) { _, _ in sample() }
            .onChange(of: isCovered) { _, _ in sample() }
            .onChange(of: state.isSearchPresented) { _, _ in sample() }
            .onDisappear {
                state.setWorkspacePresented(false)
                state.setTimeTrackingActive(false)
            }
    }
}
