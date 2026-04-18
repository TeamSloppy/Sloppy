import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Shared helpers for OpenAI-compatible `/v1/models` catalog probes (OpenAI API, LM Studio, etc.).
enum OpenAICompatibleCatalogEndpoint {
    /// Resolves `…/v1/models` even when the base URL omits `/v1` (common for local servers).
    static func modelsListURL(baseURL: URL) -> URL {
        if baseURL.path.isEmpty || baseURL.path == "/" {
            return baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        }

        let normalizedPath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
        if normalizedPath.hasSuffix("/models") {
            return baseURL
        }
        if normalizedPath.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("models")
        }

        return baseURL.appendingPathComponent("models")
    }

    /// Allow listing models without an API key only on loopback / RFC1918 LAN (local inference servers).
    static func hostAllowsKeylessOpenAIProbe(host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        if host == "localhost" { return true }
        if host == "127.0.0.1" || host == "::1" { return true }

        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let a = parts[0]
        let b = parts[1]
        if a == 10 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        return false
    }
}
