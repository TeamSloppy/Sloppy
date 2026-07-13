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
}
#endif
