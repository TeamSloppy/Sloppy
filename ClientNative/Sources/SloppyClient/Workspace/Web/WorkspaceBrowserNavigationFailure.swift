import Foundation

enum WorkspaceBrowserNavigationFailure {
    static func isCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    static func message(for error: (any Error)?) -> String? {
        guard let error, !isCancellation(error) else { return nil }
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch native.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "The internet connection is unavailable. Check your connection and try again."
        case NSURLErrorTimedOut:
            return "The website took too long to respond. Try loading it again."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "The website could not be found. Check its address."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return "The website’s secure connection could not be verified."
        default:
            return "The page could not be loaded. Please try again."
        }
    }
}

enum BrowserConnectionSecurity: Equatable {
    case empty, connecting, secure, notSecure, mixedContent, failed
    var symbol: String {
        switch self {
        case .empty: "magnifyingglass"
        case .connecting: "globe"
        case .secure: "lock.fill"
        case .notSecure: "lock.open"
        case .mixedContent, .failed: "exclamationmark.shield"
        }
    }
    var label: String {
        switch self {
        case .empty: "Search or enter an address"
        case .connecting: "Connecting…"
        case .secure: "Encrypted connection"
        case .notSecure: "Not secure — HTTP connection"
        case .mixedContent: "This page includes insecure content"
        case .failed: "Connection could not be completed"
        }
    }
}
