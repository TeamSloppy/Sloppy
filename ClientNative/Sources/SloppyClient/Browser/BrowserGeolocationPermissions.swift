import Foundation
#if os(macOS) || os(iOS)
import ObjectiveC
import WebKit
#endif

/// Apple's public geolocation delegate is newer than the SDK used by this project.
/// Detect the public optional protocol method on the running OS, without private APIs
/// or substituting coordinates for the website's native geolocation implementation.
@MainActor
enum BrowserGeolocationPermissions {
    static let selectorName = "webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:"
    static var isSupported: Bool {
#if os(macOS) || os(iOS)
        guard let delegate = objc_getProtocol("WKUIDelegate") else { return false }
        return protocol_getMethodDescription(delegate, NSSelectorFromString(selectorName), false, true).name != nil
#else
        return false
#endif
    }
}

#if os(macOS) || os(iOS)
extension WorkspaceBrowserToolRuntime {
    // Public API: developer.apple.com/documentation/webkit/wkuidelegate/
    // webview(_:requestgeolocationpermissionfor:initiatedbyframe:decisionhandler:)
    // Explicit ObjC spelling permits building against older SDKs. On systems without
    // this public callback WebKit retains its system prompt; the custom setting is disabled.
    @objc(webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, BrowserGeolocationPermissions.isSupported,
                  let origin = BrowserSiteOrigin(origin), let frameOrigin = BrowserSiteOrigin(frame.securityOrigin),
                  origin == frameOrigin, webView.url.flatMap(BrowserSiteOrigin.init) == origin else {
                decisionHandler(.deny)
                return
            }
            let revision = documentRevision
            let allowed = await sitePermissions.authorize(origin, resource: .location) { [weak self] in
                guard let self else { return .cancel }
                return await sitePrompt.request(origin, resource: .location, in: webView)
            }
            decisionHandler(allowed && revision == documentRevision && !Task.isCancelled ? .grant : .deny)
        }
    }
}
#endif
