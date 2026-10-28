import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func workspaceSourceControlSelectsOnlyConfiguredDirectories() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sloppy-workspace-sc-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directories = [root.appendingPathComponent("first"), root.appendingPathComponent("second & third"), root.appendingPathComponent("plain")]
    for directory in directories { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    for (index, directory) in directories.prefix(2).enumerated() {
        try workspaceChangesGit(directory, ["init", "--initial-branch=branch-\(index)"])
        try workspaceChangesGit(directory, ["config", "user.email", "test@sloppy.dev"])
        try workspaceChangesGit(directory, ["config", "user.name", "SloppyTest"])
        try Data("old\n".utf8).write(to: directory.appendingPathComponent("shared.txt"))
        try workspaceChangesGit(directory, ["add", "."])
        try workspaceChangesGit(directory, ["commit", "-m", "initial"])
        try Data("new-\(index)\n".utf8).write(to: directory.appendingPathComponent("shared.txt"))
    }
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    _ = try await service.createProject(ProjectCreateRequest(id: "workspace-sc", name: "Workspace", kind: .workspace,
                                                            directoryPaths: directories.map(\.path)))
    let router = CoreRouter(service: service)
    let endpoint = "/v1/projects/workspace-sc/source-control/working-tree"
    let directoryEndpoint = endpoint + "/directory"
    for (index, directory) in directories.enumerated() {
        let query = directory.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let response = await router.handle(method: "GET", path: "\(directoryEndpoint)?directoryPath=\(query)", body: nil)
        #expect(response.status == 200)
        let status = try JSONDecoder().decode(ProjectWorkingTreeSourceControlResponse.self, from: response.body)
        if index < 2 {
            #expect(status.branch == "branch-\(index)")
            #expect(status.diff.contains("+new-\(index)"))
            #expect(status.linesAdded == 1)
            #expect(status.linesDeleted == 1)
        } else {
            #expect(!status.isRepository)
            #expect(status.message != nil)
        }
    }
    let primary = await router.handle(method: "GET", path: endpoint, body: nil)
    #expect(try JSONDecoder().decode(ProjectWorkingTreeSourceControlResponse.self, from: primary.body).branch == "branch-0")
    let missingDirectory = await router.handle(method: "GET", path: directoryEndpoint, body: nil)
    #expect(missingDirectory.status == 400)
    let outside = await router.handle(method: "GET", path: "\(directoryEndpoint)?directoryPath=\(root.path)", body: nil)
    #expect(outside.status == 400)
    let traversal = await router.handle(method: "GET", path: "\(directoryEndpoint)?directoryPath=\(directories[0].path)/..", body: nil)
    #expect(traversal.status == 400)
    let escaped = directories[0].appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: root)
    let symlink = await router.handle(method: "GET", path: "\(directoryEndpoint)?directoryPath=\(escaped.path)", body: nil)
    #expect(symlink.status == 400)
}

private func workspaceChangesGit(_ directory: URL, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "WorkspaceChangesGit", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
    }
}
