import Foundation
import Testing
@testable import sloppy
@testable import Protocols

private func makeExternalProjectDirectory(prefix: String = "open-project") throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test
func createProjectWithRepoPathKeepsArtifactsLocalWithoutWorkspaceLink() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let externalDirectory = try makeExternalProjectDirectory()
    defer { try? FileManager.default.removeItem(at: externalDirectory) }

    let projectID = "open-project-\(UUID().uuidString.prefix(8).lowercased())"
    let outcome = try await service.createProject(
        ProjectCreateRequest(
            id: projectID,
            name: "Open Project",
            description: "External directory",
            channels: [],
            repoPath: externalDirectory.path
        )
    )
    let project = outcome.project

    #expect(project.repoPath == externalDirectory.path)

    let workspaceRoot = config.resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
    let projectRoot = workspaceRoot
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent(projectID, isDirectory: true)
    let sourceLink = projectRoot.appendingPathComponent("source", isDirectory: true)
    let metaDirectory = projectRoot.appendingPathComponent(".meta", isDirectory: true)

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: metaDirectory.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)

    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sourceLink.path)) == nil)
    #expect(!FileManager.default.fileExists(atPath: sourceLink.path))

    #expect(!FileManager.default.fileExists(atPath: externalDirectory.appendingPathComponent("artifacts").path))
    #expect(!FileManager.default.fileExists(atPath: externalDirectory.appendingPathComponent("logs").path))
    #expect(!FileManager.default.fileExists(atPath: externalDirectory.appendingPathComponent(".meta").path))
}

@Test
func createProjectWithRepoPathRemovesLegacyWorkspaceLink() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let externalDirectory = try makeExternalProjectDirectory()
    let legacyDestination = try makeExternalProjectDirectory(prefix: "legacy-open-project")
    defer { try? FileManager.default.removeItem(at: externalDirectory) }
    defer { try? FileManager.default.removeItem(at: legacyDestination) }

    let projectID = "open-project-legacy-\(UUID().uuidString.prefix(8).lowercased())"
    let workspaceRoot = config.resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
    let projectRoot = workspaceRoot
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent(projectID, isDirectory: true)
    let sourceLink = projectRoot.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: legacyDestination)

    _ = try await service.createProject(
        ProjectCreateRequest(
            id: projectID,
            name: "Open Project Legacy",
            description: "External directory",
            channels: [],
            repoPath: externalDirectory.path
        )
    )

    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sourceLink.path)) == nil)
    #expect(!FileManager.default.fileExists(atPath: sourceLink.path))
}

@Test
func createProjectWithRepoPathAllowsProjectFileBrowsing() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let externalDirectory = try makeExternalProjectDirectory()
    defer { try? FileManager.default.removeItem(at: externalDirectory) }

    let nestedDirectory = externalDirectory.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: nestedDirectory.appendingPathComponent("README.md"))

    let projectID = "open-project-files-\(UUID().uuidString.prefix(8).lowercased())"
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: projectID,
            name: "Open Project Files",
            description: "External directory",
            channels: [],
            repoPath: externalDirectory.path
        )
    )
    let createResponse = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(createResponse.status == 201)

    let listResponse = await router.handle(method: "GET", path: "/v1/projects/\(projectID)/files?path=Sources", body: nil)
    #expect(listResponse.status == 200)
    let listEntries = try JSONDecoder().decode([ProjectFileEntry].self, from: listResponse.body)
    #expect(listEntries.count == 1)
    #expect(listEntries[0].name == "README.md")

    let contentResponse = await router.handle(
        method: "GET",
        path: "/v1/projects/\(projectID)/files/content?path=Sources/README.md",
        body: nil
    )
    #expect(contentResponse.status == 200)
    let content = try JSONDecoder().decode(ProjectFileContentResponse.self, from: contentResponse.body)
    #expect(content.content == "hello")
    #expect(content.path == "Sources/README.md")
}

@Test
func createProjectWithMissingRepoPathReturnsBadRequest() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let missingPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("open-project-missing-\(UUID().uuidString)", isDirectory: true)
    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: "missing-open-project",
            name: "Missing Open Project",
            description: "Missing path",
            channels: [],
            repoPath: missingPath.path
        )
    )

    let response = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(response.status == 400)
}

@Test
func createProjectWithFileRepoPathReturnsBadRequest() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("open-project-file-\(UUID().uuidString).txt")
    try Data("not a directory".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: "file-open-project",
            name: "File Open Project",
            description: "File path",
            channels: [],
            repoPath: fileURL.path
        )
    )

    let response = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(response.status == 400)
}

@Test
func createProjectWithMalformedFileURLReturnsBadRequest() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let createBody = try JSONEncoder().encode(
        ProjectCreateRequest(
            id: "malformed-open-project",
            name: "Malformed Open Project",
            description: "Malformed file URL",
            channels: [],
            repoPath: "file://remote-host/tmp/project"
        )
    )

    let response = await router.handle(method: "POST", path: "/v1/projects", body: createBody)
    #expect(response.status == 400)
}
