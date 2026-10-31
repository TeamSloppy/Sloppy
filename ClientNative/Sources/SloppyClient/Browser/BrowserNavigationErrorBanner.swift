import SwiftUI
import SloppyClientUI

/// Browser errors belong above navigation backdrops so they remain readable and actionable.
struct BrowserNavigationErrorBanner: View {
    let page: WorkspaceWebViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        if let error = page.lastError {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn’t load this page").font(.callout.weight(.medium))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Retry", action: page.reload)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("browser-navigation-retry")
                    if let url = WorkspaceBrowserAddress.httpAlternative(for: URL(string: page.addressText)) {
                        Button("Open using HTTP") {
                            page.addressText = url.absoluteString
                            page.openAddress()
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(14)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.border, lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser-navigation-error")
        }
    }

    private var background: Color {
#if os(iOS)
        Color(uiColor: .secondarySystemBackground)
#else
        theme.colors.surfaceRaised
#endif
    }
}
