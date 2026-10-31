#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    @Entry var mobileWorkBrowseSelection: Binding<Bool>? = nil
}

@MainActor
struct MobileWorkBrowsePicker: View {
    @Binding var isBrowsing: Bool

    var body: some View {
        HStack(spacing: 0) {
            mode("Work", symbol: "briefcase", browsing: false)
            mode("Browse", symbol: "globe", browsing: true)
        }
        .padding(2)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-mode-picker")
    }

    private func mode(_ title: String, symbol: String, browsing: Bool) -> some View {
        Button { isBrowsing = browsing } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 36, height: 36)
                .background {
                    if isBrowsing == browsing { Circle().fill(.primary.opacity(0.1)) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isBrowsing == browsing ? .isSelected : [])
        .accessibilityIdentifier(browsing ? "workspace-mode-browse" : "workspace-mode-work")
    }
}

private struct MobileWorkBrowseNavigationBar: ViewModifier {
    @Environment(\.mobileWorkBrowseSelection) private var selection

    func body(content: Content) -> some View {
        content.toolbar {
            if let selection {
                ToolbarItem(placement: .topBarLeading) {
                    MobileWorkBrowsePicker(isBrowsing: selection)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

extension View {
    func mobileWorkBrowseNavigationBar() -> some View {
        modifier(MobileWorkBrowseNavigationBar())
    }
}
#endif
