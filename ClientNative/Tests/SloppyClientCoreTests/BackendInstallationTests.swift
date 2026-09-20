#if os(macOS)
import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Backend installation")
struct BackendInstallationTests {
    @Test("Release metadata decodes GitHub assets")
    func releaseMetadataDecodes() throws {
        let data = Data(#"{"tag_name":"v1.2.3","assets":[{"name":"Sloppy-macos-arm64.tar.gz","browser_download_url":"https://example.com/sloppy.tar.gz","size":42}]}"#.utf8)
        let release = try JSONDecoder().decode(SloppyRelease.self, from: data)
        #expect(release.tagName == "v1.2.3")
        #expect(release.assets.first?.name == "Sloppy-macos-arm64.tar.gz")
        #expect(release.assets.first?.size == 42)
    }

    @Test("Checksum parser accepts common SHA256SUMS formats")
    func checksumParser() {
        let sums = "abc123  Sloppy-linux-x86_64.tar.gz\ndef456 *Sloppy-macos-arm64.tar.gz\n"
        #expect(BackendInstaller.checksum(for: "Sloppy-macos-arm64.tar.gz", in: sums) == "def456")
        #expect(BackendInstaller.checksum(for: "missing.tar.gz", in: sums) == nil)
    }

    @Test("Installed detection requires an executable")
    func installedDetection() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let binary = BackendInstaller.installedExecutableURL(installationRoot: root)
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: binary)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!BackendInstaller.isInstalled(installationRoot: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        #expect(BackendInstaller.isInstalled(installationRoot: root))
    }

    @Test("Local backend locator prefers the app-managed executable")
    func localBackendLocatorPrefersManagedExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let managedRoot = root.appending(path: "managed", directoryHint: .isDirectory)
        let managedBinary = BackendInstaller.installedExecutableURL(installationRoot: managedRoot)
        let pathBinary = root.appending(path: "path/sloppy")
        for binary in [managedBinary, pathBinary] {
            try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let located = LocalBackendExecutableLocator.installedExecutableURL(
            homeDirectory: root,
            environment: ["PATH": pathBinary.deletingLastPathComponent().path],
            managedInstallationRoot: managedRoot
        )

        #expect(located?.standardizedFileURL == managedBinary.standardizedFileURL)
    }

    @Test("Local backend launcher does not start for a remote server")
    @MainActor
    func localBackendLauncherRejectsRemoteServer() async throws {
        let launcher = LocalBackendLauncher(
            managedInstallationRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            healthProbe: { _, _ in false }
        )

        let result = await launcher.ensureRunning(at: try #require(URL(string: "https://sloppy.example")))

        #expect(result == .unavailable)
    }
}
#endif
