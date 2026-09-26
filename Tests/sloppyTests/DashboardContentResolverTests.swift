import Foundation
import Testing
@testable import sloppy

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
