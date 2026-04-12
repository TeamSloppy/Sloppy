import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

/// HTTP(S) fetch for `web.fetch` — respects `AgentToolsGuardrails` web limits and private-network policy.
struct WebFetchService: Sendable {
    static let shared = WebFetchService()

    private init() {}

    struct Response: Sendable, Equatable {
        let finalURL: String
        let status: Int
        let contentType: String?
        let body: String
        /// True when UTF-8 decoding used replacement characters for invalid sequences.
        let lossyText: Bool
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidURL
        case schemeNotAllowed
        case hostBlocked
        case responseTooLarge
        case transport
    }

    func fetch(
        urlString: String,
        guardrails: AgentToolsGuardrails
    ) async -> Result<Response, Failure> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return .failure(.invalidURL)
        }
        guard scheme == "https" || scheme == "http" else {
            return .failure(.schemeNotAllowed)
        }
        guard let host = url.host, !host.isEmpty else {
            return .failure(.invalidURL)
        }
        if Self.policyBlocksHost(host: host, blockPrivateNetworks: guardrails.webBlockPrivateNetworks) {
            return .failure(.hostBlocked)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (compatible; SloppyBot/1.0; +https://sloppy.team)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = max(0.2, Double(guardrails.webTimeoutMs) / 1000.0)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transport)
            }
            guard data.count <= guardrails.webMaxBytes else {
                return .failure(.responseTooLarge)
            }
            let ctype = http.value(forHTTPHeaderField: "Content-Type")
            let (text, lossy) = decodeBody(data)
            let final = http.url?.absoluteString ?? trimmed
            return .success(
                Response(
                    finalURL: final,
                    status: http.statusCode,
                    contentType: ctype,
                    body: text,
                    lossyText: lossy
                )
            )
        } catch {
            return .failure(.transport)
        }
    }

    private func decodeBody(_ data: Data) -> (String, Bool) {
        if let s = String(data: data, encoding: .utf8) {
            return (s, false)
        }
        return (String(decoding: data, as: UTF8.self), true)
    }

    /// Best-effort SSRF guard: literal IPs, localhost, `.local`, and obvious IPv6 ULA/link-local/loopback.
    /// Does not resolve DNS — hostnames that map to private IPs are not blocked here.
    internal static func policyBlocksHost(host: String, blockPrivateNetworks: Bool) -> Bool {
        guard blockPrivateNetworks else { return false }
        let hostNorm = stripBrackets(host).lowercased()
        if hostNorm == "localhost" || hostNorm == "localhost." {
            return true
        }
        if hostNorm.hasSuffix(".local") || hostNorm.hasSuffix(".localhost") {
            return true
        }
        if isPrivateIPv4String(hostNorm) {
            return true
        }
        if hostNorm.contains(":") {
            return isBlockedIPv6(hostNorm)
        }
        return false
    }

    private static func stripBrackets(_ host: String) -> String {
        if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func isPrivateIPv4String(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]), let d = Int(parts[3]),
              (0...255).contains(a), (0...255).contains(b), (0...255).contains(c), (0...255).contains(d)
        else {
            return false
        }
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 0 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && b >= 16 && b <= 31 { return true }
        if a == 192 && b == 168 { return true }
        if a == 100 && b >= 64 && b <= 127 { return true }
        if a == 198 && (b == 18 || b == 19) { return true }
        return false
    }

    private static func isBlockedIPv6(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "::1" { return true }
        if h.hasPrefix("fe80:") { return true }
        if h.hasPrefix("fc") || h.hasPrefix("fd") { return true }
        if h == "::" { return true }
        return false
    }
}
