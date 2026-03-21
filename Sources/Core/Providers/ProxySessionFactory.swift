import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ProxySessionFactory {
    static func makeSession(proxy: CoreConfig.Proxy) -> URLSession {
        guard proxy.enabled, !proxy.host.isEmpty else {
            return URLSession(configuration: .default)
        }

        #if canImport(FoundationNetworking)
        return makeSessionLinux(proxy: proxy)
        #else
        return makeSessionDarwin(proxy: proxy)
        #endif
    }

    #if !canImport(FoundationNetworking)
    private static func makeSessionDarwin(proxy: CoreConfig.Proxy) -> URLSession {
        let config = URLSessionConfiguration.default
        var proxyDict: [AnyHashable: Any] = [:]

        switch proxy.type {
        case .socks5:
            proxyDict[kCFNetworkProxiesSOCKSEnable as String] = 1
            proxyDict[kCFNetworkProxiesSOCKSProxy as String] = proxy.host
            proxyDict[kCFNetworkProxiesSOCKSPort as String] = proxy.port
        case .http:
            proxyDict["HTTPEnable"] = 1
            proxyDict["HTTPProxy"] = proxy.host
            proxyDict["HTTPPort"] = proxy.port
            proxyDict["HTTPSEnable"] = 1
            proxyDict["HTTPSProxy"] = proxy.host
            proxyDict["HTTPSPort"] = proxy.port
        case .https:
            proxyDict["HTTPSEnable"] = 1
            proxyDict["HTTPSProxy"] = proxy.host
            proxyDict["HTTPSPort"] = proxy.port
        }

        config.connectionProxyDictionary = proxyDict
        return URLSession(configuration: config)
    }
    #endif

    #if canImport(FoundationNetworking)
    private static func makeSessionLinux(proxy: CoreConfig.Proxy) -> URLSession {
        let proxyURL = buildProxyURL(proxy: proxy)
        if let url = proxyURL {
            switch proxy.type {
            case .socks5:
                setenv("ALL_PROXY", url, 1)
                setenv("all_proxy", url, 1)
            case .http:
                setenv("HTTP_PROXY", url, 1)
                setenv("http_proxy", url, 1)
                setenv("HTTPS_PROXY", url, 1)
                setenv("https_proxy", url, 1)
            case .https:
                setenv("HTTPS_PROXY", url, 1)
                setenv("https_proxy", url, 1)
            }
        }
        return URLSession(configuration: .default)
    }

    private static func buildProxyURL(proxy: CoreConfig.Proxy) -> String? {
        let scheme: String
        switch proxy.type {
        case .socks5: scheme = "socks5"
        case .http: scheme = "http"
        case .https: scheme = "https"
        }

        let auth = proxy.username.isEmpty ? "" : "\(proxy.username):\(proxy.password)@"
        return "\(scheme)://\(auth)\(proxy.host):\(proxy.port)"
    }
    #endif
}
