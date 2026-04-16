import Foundation
import Testing
@testable import sloppy

@Test
func updatesCheckEndpointIncludesBuildMetadataFields() async throws {
    let checker = UpdateCheckerService(
        buildMetadataProvider: {
            BuildMetadata(
                isReleaseBuild: false,
                displayVersion: "4f0a1704cd6a (main)",
                releaseVersion: nil,
                deploymentKind: .local,
                git: GitRepositoryMetadata(
                    repositoryRootPath: "/tmp/sloppy",
                    currentCommit: "4f0a1704cd6a",
                    currentCommitFull: "4f0a1704cd6a92e01168c3b7e57645d236d8aa82",
                    currentBranch: "main",
                    currentCommitDate: ISO8601DateFormatter().date(from: "2026-04-10T10:00:00Z"),
                    upstreamBranch: "main",
                    upstreamRemoteURL: "https://github.com/TeamSloppy/Sloppy.git",
                    githubRemote: nil
                )
            )
        }
    )
    let service = CoreService(
        config: .test,
        builtInGatewayPluginFactory: .live,
        updateChecker: checker
    )
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "GET", path: "/v1/updates/check", body: nil)

    #expect(response.status == 200)

    let json = try #require(
        JSONSerialization.jsonObject(with: response.body) as? [String: Any]
    )
    #expect(json["currentVersion"] as? String == "4f0a1704cd6a (main)")
    #expect(json["deploymentKind"] as? String == "local")
    #expect(json["currentCommit"] as? String == "4f0a1704cd6a")
    #expect(json["currentBranch"] as? String == "main")
    #expect(json["updateKind"] as? String == "git")
}
