import SwiftUI

/// Fetch only from the visited site's origin, without a third-party icon service.
struct BrowserFaviconView: View {
    let pageURL: URL?
    var size: CGFloat = 16
    var body: some View {
        AsyncImage(url: Self.iconURL(for: pageURL)) { phase in
            if case .success(let image) = phase {
                image.renderingMode(.original).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }

    static func iconURL(for pageURL: URL?) -> URL? {
        guard let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              pageURL.host != nil, var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
