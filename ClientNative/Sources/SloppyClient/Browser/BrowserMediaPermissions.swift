#if os(macOS) || os(iOS)
import Foundation
import AVFoundation
import WebKit

extension BrowserSiteOrigin {
    @MainActor
    init?(_ origin: WKSecurityOrigin) {
        guard ["http", "https"].contains(origin.protocol), !origin.host.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = origin.protocol
        parts.host = origin.host
        parts.port = origin.port > 0 ? origin.port : nil
        guard let url = parts.url else { return nil }
        self.init(url)
    }
}

@MainActor
enum BrowserMediaPermissions {
    static func requestSystemAccess(_ resource: BrowserSiteResource) async -> Bool {
        let media: AVMediaType
        switch resource { case .camera: media = .video; case .microphone: media = .audio; default: return false }
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }
}

extension WorkspaceBrowserToolRuntime {
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        guard let origin = BrowserSiteOrigin(origin), let frameOrigin = BrowserSiteOrigin(frame.securityOrigin) else { return .deny }
        let resources: [BrowserSiteResource]
        switch type {
        case .camera: resources = [.camera]
        case .microphone: resources = [.microphone]
        case .cameraAndMicrophone: resources = [.camera, .microphone]
        @unknown default: return .deny
        }
        return await authorizeMedia(origin: origin, frameOrigin: frameOrigin, resources: resources)
    }

    func authorizeMedia(origin: BrowserSiteOrigin, frameOrigin: BrowserSiteOrigin,
                        resources: [BrowserSiteResource]) async -> WKPermissionDecision {
        // Cross-origin iframe access needs a separate embedding-origin policy. Until supported,
        // a top-level site's saved grant must never authorize a different requesting origin.
        guard origin == frameOrigin, webView.url.flatMap(BrowserSiteOrigin.init) == origin,
              !resources.isEmpty, resources.allSatisfy({ $0 == .camera || $0 == .microphone }) else { return .deny }
        let revision = documentRevision
        for resource in resources {
            let allowed = await sitePermissions.authorize(origin, resource: resource) { [weak self] in
                guard let self else { return .cancel }
                return await sitePrompt.request(origin, resource: resource, in: webView)
            }
            guard allowed, revision == documentRevision, !Task.isCancelled else { return .deny }
        }
        let versions = resources.map { sitePermissions.revision(for: origin, resource: $0) }
        for (index, resource) in resources.enumerated() {
            guard await requestSystemMediaAccess(resource), versions[index] == sitePermissions.revision(for: origin, resource: resource), revision == documentRevision, !Task.isCancelled,
                  sitePermissions.decision(for: origin, resource: resource) != .block else { return .deny }
        }
        guard resources.enumerated().allSatisfy({ index, resource in
            versions[index] == sitePermissions.revision(for: origin, resource: resource)
        }) else { return .deny }
        return .grant
    }

    func revokePermission(for origin: BrowserSiteOrigin, resource: BrowserSiteResource) {
        guard webView.url.flatMap(BrowserSiteOrigin.init) == origin else { return }
        switch resource {
        case .camera: webView.setCameraCaptureState(.none, completionHandler: nil)
        case .microphone: webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        case .location: if BrowserGeolocationPermissions.isSupported { webView.reload() }
        default: break
        }
    }
}
#endif
