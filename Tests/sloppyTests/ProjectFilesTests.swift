import Foundation
import Testing
@testable import sloppy
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
func searchProjectFilesReturnsRankedPaths() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    let srcDir = projectDir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: srcDir.appendingPathComponent("AppMain.swift"))
    try Data("y".utf8).write(to: projectDir.appendingPathComponent("readme.md"))

    let encodedQuery = "main".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "main"
    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files/search?q=\(encodedQuery)&limit=20",
        body: nil
    )
    #expect(resp.status == 200)

    let hits = try JSONDecoder().decode([ProjectFileSearchEntry].self, from: resp.body)
    let paths = hits.map(\.path)
    #expect(paths.contains("src/AppMain.swift"))
}

@Test
func searchProjectFilesEmptyQueryListsRoot() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try Data("z".utf8).write(to: projectDir.appendingPathComponent("root.txt"))

    let resp = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files/search?limit=10",
        body: nil
    )
    #expect(resp.status == 200)

    let hits = try JSONDecoder().decode([ProjectFileSearchEntry].self, from: resp.body)
    #expect(hits.contains(where: { $0.path == "root.txt" && $0.type == .file }))
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

private func runGitInProjectDir(_ cwd: URL, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = cwd
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: s])
    }
}

@Test
func projectWorkingTreeGitReturnsDiffAndStats() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try runGitInProjectDir(projectDir, ["init", "--initial-branch=main"])
    try runGitInProjectDir(projectDir, ["config", "user.email", "test@sloppy.dev"])
    try runGitInProjectDir(projectDir, ["config", "user.name", "SloppyTest"])
    try Data("v1".utf8).write(to: projectDir.appendingPathComponent("file.txt"))
    try runGitInProjectDir(projectDir, ["add", "."])
    try runGitInProjectDir(projectDir, ["commit", "-m", "init"])
    try Data("v2\nline2".utf8).write(to: projectDir.appendingPathComponent("file.txt"))

    let resp = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/git/working-tree", body: nil)
    #expect(resp.status == 200)
    let payload = try JSONDecoder().decode(ProjectWorkingTreeGitResponse.self, from: resp.body)
    #expect(payload.isGitRepository == true)
    #expect(payload.linesAdded + payload.linesDeleted > 0)
    #expect(!payload.diff.isEmpty)
}

@Test
func projectGitRestoreRevertsFileToHead() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let (projectID, projectDir) = try await makeProjectAndDir(router: router, config: config)

    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    try runGitInProjectDir(projectDir, ["init", "--initial-branch=main"])
    try runGitInProjectDir(projectDir, ["config", "user.email", "test@sloppy.dev"])
    try runGitInProjectDir(projectDir, ["config", "user.name", "SloppyTest"])
    try Data("committed".utf8).write(to: projectDir.appendingPathComponent("tracked.txt"))
    try runGitInProjectDir(projectDir, ["add", "."])
    try runGitInProjectDir(projectDir, ["commit", "-m", "init"])
    try Data("working".utf8).write(to: projectDir.appendingPathComponent("tracked.txt"))

    let body = try JSONEncoder().encode(ProjectGitRestoreRequest(path: "tracked.txt"))
    let resp = await router.handle(method: "POST", path: "/v1/projects/\(projectID)/git/restore", body: body)
    #expect(resp.status == 200)

    let restored = try String(contentsOf: projectDir.appendingPathComponent("tracked.txt"), encoding: .utf8)
    #expect(restored == "committed")
}
