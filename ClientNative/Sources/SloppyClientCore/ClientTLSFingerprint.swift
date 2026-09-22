import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

public enum ClientTLSFingerprintStore {
    private static let prefix = "client_tls_fingerprint_"

    public static func fingerprint(for baseURL: URL) -> String? {
        UserDefaults.standard.string(forKey: key(for: baseURL))
    }

    public static func set(_ fingerprint: String?, for baseURL: URL) {
        let key = key(for: baseURL)
        guard let normalized = normalized(fingerprint) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(normalized, forKey: key)
    }

    public static func normalized(_ fingerprint: String?) -> String? {
        guard let fingerprint else { return nil }
        let value = fingerprint.lowercased()
            .replacingOccurrences(of: "sha256:", with: "")
            .replacingOccurrences(of: ":", with: "")
        return value.count == 64 && value.allSatisfy(\.isHexDigit) ? value : nil
    }

    private static func key(for baseURL: URL) -> String {
        let digest = SHA256.hash(data: Data(baseURL.absoluteString.utf8))
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ClientURLSessionFactory {
    public static func session(for baseURL: URL, tlsFingerprint: String? = nil) -> URLSession {
        let fingerprint = ClientTLSFingerprintStore.normalized(tlsFingerprint)
            ?? ClientTLSFingerprintStore.fingerprint(for: baseURL)
        #if canImport(Security)
        if baseURL.scheme?.lowercased() == "https", let fingerprint {
            return URLSession(
                configuration: .default,
                delegate: PinnedCertificateDelegate(fingerprint: fingerprint),
                delegateQueue: nil
            )
        }
        #endif
        return .shared
    }
}

#if canImport(Security)
private final class PinnedCertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let fingerprint: String

    init(fingerprint: String) {
        self.fingerprint = fingerprint
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let data = SecCertificateCopyData(certificate) as Data
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#endif
