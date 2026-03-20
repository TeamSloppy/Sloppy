import Foundation
import Testing
@testable import Core
@testable import Protocols

private func makeProjectAndDir(router: CoreRouter, config: CoreConfig) async throws -> (projectID: String, projectDir: URL) {
    let projectID = "files-test-\(UUID().uuidString.prefix(8).lowercased())"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(id: projectID, name: "Files Test Project", description: "Test", channels: [])
    )
    let resp = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(resp.status == 201)

    let workspaceRoot = config.resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
    let projectDir = workspaceRoot
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent(projectID, isDirectory: true)

    return (projectID, projectDir)
}

@Test
func listProjectFilesReturnsDirectoryEntries() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: projectDir.appendingPathComponent("readme.txt"))
    let subDir = projectDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/files", body: nil)
    #expect(resp.status == 200)

    let decoder = JSONDecoder()
    let entries = try decoder.decode([ProjectFileEntry].self, from: resp.body)
    let names = entries.map(\.name)
    #expect(names.contains("readme.txt"))
    #expect(names.contains("src"))
    let srcEntry = try #require(entries.first(where: { $0.name == "src" }))
    #expect(srcEntry.type == .directory)
    let fileEntry = try #require(entries.first(where: { $0.name == "readme.txt" }))
    #expect(fileEntry.type == .file)
}

@Test
func listProjectFilesDirectoriesBeforeFiles() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try Data("a".utf8).write(to: projectDir.appendingPathComponent("afile.txt"))
    let subDir = projectDir.appendingPathComponent("bdir", isDirectory: true)
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/files", body: nil)
    #expect(resp.status == 200)

    let entries = try JSONDecoder().decode([ProjectFileEntry].self, from: resp.body)
    #expect(entries.first?.type == .directory)
}

@Test
func listProjectFilesSubdirectory() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    let subDir = projectDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
    try Data("content".utf8).write(to: subDir.appendingPathComponent("main.swift"))

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files?path=src",
        body: nil
    )
    #expect(resp.status == 200)

    let entries = try JSONDecoder().decode([ProjectFileEntry].self, from: resp.body)
    #expect(entries.count == 1)
    #expect(entries[0].name == "main.swift")
    #expect(entries[0].type == .file)
}

@Test
func listProjectFilesReturns404ForUnknownProject() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let resp = await router.handle(method: "GET", path: "/v1/projects/nonexistent/files", body: nil)
    #expect(resp.status == 404)
}

@Test
func readProjectFileReturnsContent() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    let text = "Hello, World!"
    try Data(text.utf8).write(to: projectDir.appendingPathComponent("hello.txt"))

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files/content?path=hello.txt",
        body: nil
    )
    #expect(resp.status == 200)

    let result = try JSONDecoder().decode(ProjectFileContentResponse.self, from: resp.body)
    #expect(result.content == text)
    #expect(result.path == "hello.txt")
    #expect(result.sizeBytes == text.utf8.count)
}

@Test
func readProjectFileReturns404ForUnknownProject() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/nonexistent/files/content?path=file.txt",
        body: nil
    )
    #expect(resp.status == 404)
}

@Test
func readProjectFileRejectsPathTraversal() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, _) = try await makeProjectAndDir(router: router, config: config)

    let escapePath = "../../../etc/passwd"
    let encodedPath = escapePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? escapePath
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files/content?path=\(encodedPath)",
        body: nil
    )
    #expect(resp.status == 400 || resp.status == 404)
}

@Test
func listProjectFilesRejectsPathTraversal() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, _) = try await makeProjectAndDir(router: router, config: config)

    let escapePath = "../../etc"
    let encodedPath = escapePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? escapePath
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files?path=\(encodedPath)",
        body: nil
    )
    #expect(resp.status == 400 || resp.status == 404)
}
