import Foundation
import Testing
@testable import sloppy

@Test
func sloppyVersionIsNewerPatch() {
    #expect(SloppyVersion.isNewer("1.2.4", than: "1.2.3") == true)
}

@Test
func sloppyVersionIsNewerMinor() {
    #expect(SloppyVersion.isNewer("1.3.0", than: "1.2.9") == true)
}

@Test
func sloppyVersionIsNewerMajor() {
    #expect(SloppyVersion.isNewer("2.0.0", than: "1.9.9") == true)
}

@Test
func sloppyVersionNotNewerWhenEqual() {
    #expect(SloppyVersion.isNewer("1.2.3", than: "1.2.3") == false)
}

@Test
func sloppyVersionNotNewerWhenOlder() {
    #expect(SloppyVersion.isNewer("1.2.2", than: "1.2.3") == false)
}

@Test
func sloppyVersionNewerWithMissingSegment() {
    #expect(SloppyVersion.isNewer("2.0", than: "1.9.9") == true)
}

@Test
func sloppyVersionNotNewerWithMissingSegment() {
    #expect(SloppyVersion.isNewer("1.2", than: "1.2.1") == false)
}

@Test
func sloppyVersionDevBuildDetection() {
    // In test builds the resource bundle contains the placeholder,
    // so isReleaseBuild should be false.
    #expect(SloppyVersion.isReleaseBuild == false)
    #expect(SloppyVersion.current == "__SLOPPY_APP_VERSION__")
}

@Test
func updateCheckerDevBuildSkipsCheck() async {
    let checker = UpdateCheckerService()
    let status = await checker.status()
    // Dev builds never report updateAvailable and never set latestVersion.
    #expect(status.isReleaseBuild == false)
    #expect(status.updateAvailable == false)
    #expect(status.latestVersion == nil)
}

@Test
func updateCheckerForceCheckDevBuild() async {
    let checker = UpdateCheckerService()
    let status = await checker.forceCheck()
    #expect(status.isReleaseBuild == false)
    #expect(status.updateAvailable == false)
}
