import Foundation
import Logging
import Testing
@testable import sloppy
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Test(arguments: [false, true])
func dashboardRuntimeConfigPreservesSidebarProjectChatsFlag(enabled: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let templateURL = directory.appendingPathComponent("config.json")
    try Data("""
    {"apiBase":"http://old-host","features":{"sidebarProjectChats":\(enabled)}}
    """.utf8).write(to: templateURL)

    let resolver = DashboardContentResolver(
        rootURL: directory,
        templateConfigURL: templateURL,
        apiBase: "http://127.0.0.1:25101"
    )
    let payload = try #require(JSONSerialization.jsonObject(with: resolver.runtimeConfigData()) as? [String: Any])
    let features = try #require(payload["features"] as? [String: Bool])

    #expect(payload["apiBase"] as? String == "http://127.0.0.1:25101")
    #expect(features["sidebarProjectChats"] == enabled)
}

@Test(arguments: ["127.0.0.1", "::1", "::ffff:127.0.0.1", "192.168.3.43", nil] as [String?])
func dashboardRuntimeConfigUsesLoopbackForLocalConnections(localAddress: String?) throws {
    let resolver = DashboardContentResolver(
        rootURL: FileManager.default.temporaryDirectory,
        templateConfigURL: nil,
        apiBase: "http://192.168.3.43:25101",
        localAPIBase: "http://127.0.0.1:25101"
    )
    let response = resolver.response(for: "GET", uri: "/config.json", localAddress: localAddress)
    let config = try JSONDecoder().decode(DashboardClientConfig.self, from: response.body)

    #expect(response.status == 200)
    #expect(response.headers["cache-control"] == "no-store")
    #expect(config.apiBase == (localAddress == nil || localAddress == "192.168.3.43"
        ? "http://192.168.3.43:25101" : "http://127.0.0.1:25101"))
}

@Test func dashboardRuntimeConfigDoesNotInventLoopbackForLANOnlyCore() throws {
    let resolver = DashboardContentResolver(
        rootURL: FileManager.default.temporaryDirectory,
        templateConfigURL: nil,
        apiBase: "http://192.168.3.43:25101"
    )
    let response = resolver.response(for: "GET", uri: "/config.json", localAddress: "127.0.0.1")
    let config = try JSONDecoder().decode(DashboardClientConfig.self, from: response.body)

    #expect(config.apiBase == "http://192.168.3.43:25101")
}

@Test func dashboardHTTPServerKeepsLocalConsoleRequestsOnLoopback() async throws {
    let logger = Logger.sloppy(label: "sloppy.dashboard.config.tests")
    let service = CoreService(config: .test)
    let coreServer = CoreHTTPServer(host: "127.0.0.1", port: 0, router: CoreRouter(service: service), logger: logger)
    try coreServer.start()
    defer { try? coreServer.shutdown() }
    let apiPort = try #require(coreServer.boundPort)
    let localAPIBase = "http://127.0.0.1:\(apiPort)"
    let resolver = DashboardContentResolver(
        rootURL: FileManager.default.temporaryDirectory,
        templateConfigURL: nil,
        apiBase: "http://192.168.3.43:\(apiPort)",
        localAPIBase: localAPIBase
    )
    let server = DashboardHTTPServer(
        host: "127.0.0.1", port: 0, responder: resolver,
        logger: logger
    )
    try server.start()
    defer { try? server.shutdown() }
    let port = try #require(server.boundPort)
    let url = try #require(URL(string: "http://127.0.0.1:\(port)/config.json"))
    let (data, response) = try await URLSession.shared.data(from: url)
    let config = try JSONDecoder().decode(DashboardClientConfig.self, from: data)

    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "cache-control") == "no-store")
    #expect(config.apiBase == localAPIBase)

    let apiBase = try #require(config.apiBase)
    let accountURL = try #require(URL(string: "\(apiBase)/v1/console/account?environment=production"))
    var request = URLRequest(url: accountURL)
    request.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "origin")
    let (accountData, accountResponse) = try await URLSession.shared.data(for: request)
    let account = try #require(JSONSerialization.jsonObject(with: accountData) as? [String: Any])

    #expect((accountResponse as? HTTPURLResponse)?.statusCode == 200)
    #expect(account["signedIn"] as? Bool == false)
}
