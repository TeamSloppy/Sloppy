import Foundation
import Testing

@Suite("Project files API client source")
struct ProjectFilesAPIClientSourceTests {
    private func source(named name: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SloppyClientCore")
            .appendingPathComponent(name)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    @Test("client exposes project file list and content helpers")
    func clientExposesProjectFileHelpers() throws {
        let apiClient = try source(named: "SloppyAPIClient.swift")
        let services = try source(named: "BackendServices.swift")

        #expect(apiClient.contains("fetchProjectFiles(projectId: String, path: String = \"\")"))
        #expect(apiClient.contains("fetchProjectFileContent(projectId: String, path: String)"))
        #expect(services.contains("public func fetchProjectFiles(projectId: String, path: String = \"\") async throws -> [ProjectFileEntry]"))
        #expect(services.contains("public func fetchProjectFileContent(projectId: String, path: String) async throws -> ProjectFileContentResponse"))
        #expect(services.contains("\"/v1/projects/\\(BackendHTTPClient.encodePathSegment(projectId))/files"))
        #expect(services.contains("\"/v1/projects/\\(BackendHTTPClient.encodePathSegment(projectId))/files/content?path="))
    }
}
