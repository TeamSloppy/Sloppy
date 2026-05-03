import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Security)
import Security
#endif

enum SloppyURLSessionFactory {
    static let extraCACertsEnvironmentKey = "SLOPPY_CA_CERTS"

    static let shared: URLSession = makeSession()

    static func makeSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        SloppyExtraCertificateAuthority.configureProcessEnvironmentIfNeeded()

        #if canImport(Security)
        if SloppyExtraCertificateAuthority.hasConfiguredCertificates {
            return URLSession(
                configuration: configuration,
                delegate: SloppyCertificateAuthorityURLSessionDelegate(),
                delegateQueue: nil
            )
        }
        #endif

        return URLSession(configuration: configuration)
    }
}

enum SloppyExtraCertificateAuthority {
    static var hasConfiguredCertificates: Bool {
        !configuredCertificateData().isEmpty
    }

    static func configureProcessEnvironmentIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let path = configuredPath(environment: environment) else { return }

        #if canImport(FoundationNetworking)
        if getenv("SSL_CERT_FILE") == nil {
            setenv("SSL_CERT_FILE", path, 0)
        }
        if getenv("CURL_CA_BUNDLE") == nil {
            setenv("CURL_CA_BUNDLE", path, 0)
        }
        #endif
    }

    static func configuredCertificateData(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Data] {
        guard let path = configuredPath(environment: environment),
              let fileData = try? Data(contentsOf: URL(fileURLWithPath: path))
        else {
            return []
        }

        if let text = String(data: fileData, encoding: .utf8) {
            let pemCertificates = certificateData(fromPEM: text)
            if !pemCertificates.isEmpty {
                return pemCertificates
            }
        }

        return [fileData]
    }

    static func certificateData(fromPEM pem: String) -> [Data] {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        var remaining = pem[...]
        var certificates: [Data] = []

        while let beginRange = remaining.range(of: begin),
              let endRange = remaining.range(of: end) {
            let body = remaining[beginRange.upperBound..<endRange.lowerBound]
            let base64 = body
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined()

            if let data = Data(base64Encoded: base64) {
                certificates.append(data)
            }

            remaining = remaining[endRange.upperBound...]
        }

        return certificates
    }

    private static func configuredPath(environment: [String: String]) -> String? {
        let raw = environment[SloppyURLSessionFactory.extraCACertsEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return NSString(string: raw).expandingTildeInPath
    }
}

#if canImport(Security)
extension SloppyExtraCertificateAuthority {
    static func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            return false
        }

        let certificates = configuredCertificateData()
            .compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty else {
            return false
        }

        SecTrustSetAnchorCertificates(trust, certificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
        return true
    }
}

private final class SloppyCertificateAuthorityURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if SloppyExtraCertificateAuthority.handle(challenge: challenge, completionHandler: completionHandler) {
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
#endif
