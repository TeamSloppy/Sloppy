#if os(macOS)
import Foundation
import AuthenticationServices
import Observation
import Security

enum BrowserPasskeyAuthorization: Sendable {
    case unavailable, notDetermined, authorized, denied

    init(_ state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState) {
        switch state {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .notDetermined: self = .notDetermined
        @unknown default: self = .unavailable
        }
    }
}

/// Browser-wide consent only. WebKit retains the website challenge and presents
/// the system credential picker; Sloppy never reads or forwards credential data.
@Observable
@MainActor
final class BrowserPasskeyAccess {
    private(set) var authorization: BrowserPasskeyAuthorization = .unavailable
    private(set) var isRequesting = false
    private let hasEntitlement: () -> Bool
    private let readAuthorization: () -> BrowserPasskeyAuthorization
    private let requestAuthorization: () async -> BrowserPasskeyAuthorization

    init(
        hasEntitlement: @escaping () -> Bool,
        readAuthorization: @escaping () -> BrowserPasskeyAuthorization,
        requestAuthorization: @escaping () async -> BrowserPasskeyAuthorization
    ) {
        self.hasEntitlement = hasEntitlement
        self.readAuthorization = readAuthorization
        self.requestAuthorization = requestAuthorization
    }

    convenience init() {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        self.init(
            hasEntitlement: {
                guard let task = SecTaskCreateFromSelf(nil) else { return false }
                return SecTaskCopyValueForEntitlement(task,
                    "com.apple.developer.web-browser.public-key-credential" as CFString, nil) as? Bool == true
            },
            readAuthorization: { BrowserPasskeyAuthorization(manager.authorizationStateForPlatformCredentials) },
            requestAuthorization: {
                await withCheckedContinuation { continuation in
                    manager.requestAuthorizationForPublicKeyCredentials { state in
                        continuation.resume(returning: BrowserPasskeyAuthorization(state))
                    }
                }
            }
        )
    }

    func refresh() {
        guard !isRequesting else { return }
        authorization = hasEntitlement() ? readAuthorization() : .unavailable
    }

    func requestAccess() async {
        guard !isRequesting else { return }
        refresh()
        guard authorization == .notDetermined else { return }
        isRequesting = true
        defer { isRequesting = false }
        authorization = await requestAuthorization()
    }
}
#endif
