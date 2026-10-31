#if os(iOS)
import SwiftUI
import UIKit

struct MobileBrowserChromeSchemePreferenceKey: PreferenceKey {
    static let defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) {
        if let next = nextValue() { value = next }
    }
}

/// The window owns status-bar appearance; a visible page can supply its contrast.
struct MobileBrowserChromeSchemeModifier: ViewModifier {
    let fallback: ColorScheme
    var allowsPageScheme = true
    @State private var pageScheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(MobileBrowserChromeSchemePreferenceKey.self) { pageScheme = $0 }
            .preferredColorScheme(allowsPageScheme ? pageScheme ?? fallback : fallback)
    }
}

enum MobileBrowserPageAppearance {
    static func isDark(_ color: UIColor, traits: UITraitCollection) -> Bool {
        let resolved = color.resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0 else {
            return traits.userInterfaceStyle == .dark
        }
        return red * 0.299 + green * 0.587 + blue * 0.114 < 0.6
    }
}
#endif
