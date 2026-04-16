import Foundation
import Testing
@testable import sloppy

private func makeGitBuildMetadata(
    currentCommit: String = "4f0a1704cd6a",
    currentBranch: String = "main",
    currentCommitDate: Date? = ISO8601DateFormatter().date(from: "2026-04-10T10:00:00Z"),
    upstreamBranch: String? = "main",
    githubRemote: GitHubRemoteDescriptor? = GitHubRemoteDescriptor(owner: "TeamSloppy", repo: "Sloppy", branch: "main")
) -> BuildMetadata {
    BuildMetadata(
        isReleaseBuild: false,
        displayVersion: "\(currentCommit) (\(currentBranch))",
        releaseVersion: nil,
        deploymentKind: .local,
        git: GitRepositoryMetadata(
            repositoryRootPath: "/tmp/sloppy",
            currentCommit: currentCommit,
            currentCommitFull: "\(currentCommit)92e01168c3b7e57645d236d8aa82",
            currentBranch: currentBranch,
            currentCommitDate: currentCommitDate,
            upstreamBranch: upstreamBranch,
            upstreamRemoteURL: githubRemote == nil ? nil : "https://github.com/TeamSloppy/Sloppy.git",
            githubRemote: githubRemote
        )
    )
}

@Test
func updateCheckerGitBuildDetectsNewerUpstreamCommit() async throws {
    let checker = UpdateCheckerService(
        buildMetadataProvider: { makeGitBuildMetadata() },
        gitCommitFetcher: { descriptor, _ in
            #expect(descriptor == GitHubRemoteDescriptor(owner: "TeamSloppy", repo: "Sloppy", branch: "main"))
            return .init(
                latestCommit: "abcdef123456",
                latestCommitDate: ISO8601DateFormatter().date(from: "2026-04-12T10:00:00Z")
            )
        }
    )

    let status = await checker.forceCheck()

    #expect(status.updateKind == .git)
    #expect(status.updateAvailable == true)
    #expect(status.latestCommit == "abcdef123456")
    #expect(status.latestBranch == "main")
}

@Test
func updateCheckerGitBuildIgnoresOlderUpstreamCommit() async throws {
    let checker = UpdateCheckerService(
        buildMetadataProvider: { makeGitBuildMetadata() },
        gitCommitFetcher: { _, _ in
            .init(
                latestCommit: "abcdef123456",
                latestCommitDate: ISO8601DateFormatter().date(from: "2026-04-09T10:00:00Z")
            )
        }
    )

    let status = await checker.forceCheck()

    #expect(status.updateAvailable == false)
    #expect(status.latestCommit == "abcdef123456")
}

@Test
func updateCheckerGitBuildWithoutUpstreamSkipsRemoteCheck() async {
    let checker = UpdateCheckerService(
        buildMetadataProvider: {
            makeGitBuildMetadata(
                upstreamBranch: nil,
                githubRemote: nil
            )
        },
        gitCommitFetcher: { _, _ in
            Issue.record("Git commit fetcher should not be called without upstream.")
            return nil
        }
    )

    let status = await checker.forceCheck()

    #expect(status.updateAvailable == false)
    #expect(status.latestCommit == nil)
    #expect(status.latestBranch == nil)
}

@Test
func updateCheckerGitBuildWithNonGitHubRemoteSkipsRemoteCheck() async {
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
                    upstreamRemoteURL: "https://gitlab.com/TeamSloppy/Sloppy.git",
                    githubRemote: nil
                )
            )
        },
        gitCommitFetcher: { _, _ in
            Issue.record("Git commit fetcher should not be called for non-GitHub remotes.")
            return nil
        }
    )

    let status = await checker.forceCheck()

    #expect(status.updateAvailable == false)
    #expect(status.latestCommit == nil)
    #expect(status.latestBranch == "main")
}
