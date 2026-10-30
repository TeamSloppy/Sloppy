#if os(macOS)
import SwiftUI

struct ToggleMainSidebarAction {
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var toggleMainSidebar: ToggleMainSidebarAction?
}

struct SidebarToggleButton: View {
    let action: ToggleMainSidebarAction?

    var body: some View {
        Button("Toggle Sidebar", systemImage: "sidebar.left") { action?() }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(action == nil)
    }
}

#endif
