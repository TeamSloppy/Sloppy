import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#else
import Network
#endif

enum ProxySessionFactory {
    static func makeSession(proxy: CoreConfig.Proxy, protocolClasses: [AnyClass] = []) -> URLSession {
        guard proxy.enabled, !proxy.host.isEmpty else {
            let config = URLSessionConfiguration.default
            config.protocolClasses = mergedProtocolClasses(protocolClasses, existing: config.protocolClasses)
            return SloppyURLSessionFactory.makeSession(configuration: config)
        }

        #if canImport(FoundationNetworking)
        return makeSessionLinux(proxy: proxy, protocolClasses: protocolClasses)
        #else
        return makeSessionDarwin(proxy: proxy, protocolClasses: protocolClasses)
        #endif
    }

    #if !canImport(FoundationNetworking)
    private static func makeSessionDarwin(proxy: CoreConfig.Proxy, protocolClasses: [AnyClass]) -> URLSession {
        let config = URLSessionConfiguration.default
        config.protocolClasses = mergedProtocolClasses(protocolClasses, existing: config.protocolClasses)

        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: proxy.port)) else {
            return SloppyURLSessionFactory.makeSession(configuration: config)
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(proxy.host),
            port: port
        )

        var proxyConfig: ProxyConfiguration
        switch proxy.type {
        case .socks5:
            proxyConfig = ProxyConfiguration(socksv5Proxy: endpoint)
        case .http:
            proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case .https:
            proxyConfig = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: .init())
        }

        if !proxy.username.isEmpty {
            proxyConfig.applyCredential(username: proxy.username, password: proxy.password)
        }

        config.proxyConfigurations = [proxyConfig]
        return SloppyURLSessionFactory.makeSession(configuration: config)
    }
    #endif

    #if canImport(FoundationNetworking)
    private static func makeSessionLinux(proxy: CoreConfig.Proxy, protocolClasses: [AnyClass]) -> URLSession {
        let url = buildProxyURL(proxy: proxy)
        setAllProxyEnv(url)
        let config = URLSessionConfiguration.default
        config.protocolClasses = mergedProtocolClasses(protocolClasses, existing: config.protocolClasses)
        return SloppyURLSessionFactory.makeSession(configuration: config)
    }

    private static func setAllProxyEnv(_ url: String) {
        for key in ["HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"] {
            setenv(key, url, 1)
        }
    }

    private static func buildProxyURL(proxy: CoreConfig.Proxy) -> String {
        let scheme: String
        switch proxy.type {
        case .socks5: scheme = "socks5h"
        case .http: scheme = "http"
        case .https: scheme = "https"
        }

        let auth = proxy.username.isEmpty ? "" : "\(proxy.username):\(proxy.password)@"
        return "\(scheme)://\(auth)\(proxy.host):\(proxy.port)"
    }
    #endif

    private static func mergedProtocolClasses(_ preferred: [AnyClass], existing: [AnyClass]?) -> [AnyClass]? {
        guard !preferred.isEmpty else { return existing }
        return preferred + (existing ?? [])
    }
}
