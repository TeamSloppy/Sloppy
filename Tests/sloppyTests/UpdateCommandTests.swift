import Foundation
import Testing
@testable import sloppy

@Test
func updateInstallerPlanUsesReleaseInstallerForReleaseBuild() throws {
    let metadata = BuildMetadata(
        isReleaseBuild: true,
        displayVersion: "1.2.3",
        releaseVersion: "1.2.3",
        deploymentKind: .local,
        git: nil
    )

    let plan = UpdateInstallerPlan(
        metadata: metadata,
        repoURL: URL(fileURLWithPath: "/tmp/Sloppy", isDirectory: true),
        scriptURL: URL(fileURLWithPath: "/tmp/Sloppy/scripts/install.sh"),
        options: .init(serverOnly: false, noGitUpdate: false, noLink: false, dryRun: false, verbose: false)
    )

    #expect(plan.kind == .release)
    #expect(plan.arguments == [
        "bash",
        "/tmp/Sloppy/scripts/install.sh",
        "--release",
        "--no-prompt",
    ])
}

@Test
func updateInstallerPlanPreservesSourceInstallerForGitBuild() throws {
    let metadata = BuildMetadata(
        isReleaseBuild: false,
        displayVersion: "67edeea420bd (main)",
        releaseVersion: nil,
        deploymentKind: .local,
        git: GitRepositoryMetadata(
            repositoryRootPath: "/tmp/Sloppy",
            currentCommit: "67edeea420bd",
            currentCommitFull: "67edeea420bd92e01168c3b7e57645d236d8aa82",
            currentBranch: "main",
            currentCommitDate: nil,
            upstreamBranch: "main",
            upstreamRemoteURL: "https://github.com/TeamSloppy/Sloppy.git",
            githubRemote: GitHubRemoteDescriptor(owner: "TeamSloppy", repo: "Sloppy", branch: "main")
        )
    )

    let plan = UpdateInstallerPlan(
        metadata: metadata,
        repoURL: URL(fileURLWithPath: "/tmp/Sloppy", isDirectory: true),
        scriptURL: URL(fileURLWithPath: "/tmp/Sloppy/scripts/install.sh"),
        options: .init(serverOnly: true, noGitUpdate: true, noLink: true, dryRun: true, verbose: true)
    )

    #expect(plan.kind == .source)
    #expect(plan.arguments == [
        "bash",
        "/tmp/Sloppy/scripts/install.sh",
        "--server-only",
        "--dir",
        "/tmp/Sloppy",
        "--no-prompt",
        "--no-git-update",
        "--no-link",
        "--dry-run",
        "--verbose",
    ])
}
