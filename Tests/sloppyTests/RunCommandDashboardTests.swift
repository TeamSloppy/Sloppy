import Foundation
import Testing
@testable import sloppy

@Test
func dashboardStartDefaultsToEnabled() {
    #expect(shouldStartDashboard(guiOverride: nil, dashboardOverride: nil))
}

@Test
func dashboardStartRespectsPrimaryGuiFlag() {
    #expect(!shouldStartDashboard(guiOverride: false, dashboardOverride: nil))
    #expect(shouldStartDashboard(guiOverride: true, dashboardOverride: false))
}

@Test
func dashboardStartFallsBackToAliasFlag() {
    #expect(!shouldStartDashboard(guiOverride: nil, dashboardOverride: false))
    #expect(shouldStartDashboard(guiOverride: nil, dashboardOverride: true))
}

@Test
func primaryLANIPv4PrefersPrivateAddressOnPreferredInterface() {
    let candidates: [NetworkIPv4Candidate] = [
        .init(interfaceName: "bridge0", address: "10.0.0.8"),
        .init(interfaceName: "en1", address: "172.20.10.2"),
        .init(interfaceName: "en0", address: "192.168.1.42"),
        .init(interfaceName: "wlan0", address: "192.168.1.55")
    ]

    #expect(NetworkAddressResolver.resolvePrimaryLANIPv4(from: candidates) == "192.168.1.42")
}

@Test
func primaryLANIPv4IgnoresLoopbackAndLinkLocalCandidates() {
    let candidates: [NetworkIPv4Candidate] = [
        .init(interfaceName: "lo0", address: "127.0.0.1"),
        .init(interfaceName: "en0", address: "169.254.12.3"),
        .init(interfaceName: "eth0", address: "8.8.8.8")
    ]

    #expect(NetworkAddressResolver.resolvePrimaryLANIPv4(from: candidates) == "8.8.8.8")
}

@Test
func wildcardBindFallsBackToLoopbackWhenLANIsUnavailable() {
    let endpoints = NetworkAddressResolver.makeDisplayEndpoints(
        bindHost: "0.0.0.0",
        apiPort: 25101,
        dashboardPort: 25102,
        lanIPv4: nil
    )

    #expect(endpoints.bindAddress == "0.0.0.0:25101")
    #expect(endpoints.localAPIURL == "http://127.0.0.1:25101")
    #expect(endpoints.lanAPIURL == nil)
    #expect(endpoints.preferredAPIBase == "http://127.0.0.1:25101")
    #expect(endpoints.preferredDashboardURL == "http://127.0.0.1:25102")
}

@Test
func explicitBindHostIsPreservedForUserFacingEndpoints() {
    let endpoints = NetworkAddressResolver.makeDisplayEndpoints(
        bindHost: "192.168.1.50",
        apiPort: 25101,
        dashboardPort: 25102,
        lanIPv4: "10.0.0.2"
    )

    #expect(endpoints.localAPIURL == nil)
    #expect(endpoints.lanAPIURL == "http://192.168.1.50:25101")
    #expect(endpoints.preferredAPIBase == "http://192.168.1.50:25101")
    #expect(endpoints.preferredDashboardURL == "http://192.168.1.50:25102")
}

@Test
func dashboardRuntimeConfigOverridesAPIBaseAndKeepsAccentColor() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let configURL = tempRoot.appendingPathComponent("config.json")
    try Data("""
    {
      "apiBase": "http://localhost:25101",
      "accentColor": "#7fff00"
    }
    """.utf8).write(to: configURL)

    let resolver = DashboardContentResolver(
        rootURL: tempRoot,
        templateConfigURL: configURL,
        apiBase: "http://192.168.1.42:25101"
    )
    let response = resolver.response(for: "GET", uri: "/config.json")
    let decoded = try JSONDecoder().decode(DashboardClientConfig.self, from: response.body)

    #expect(response.status == 200)
    #expect(decoded.apiBase == "http://192.168.1.42:25101")
    #expect(decoded.accentColor == "#7fff00")
}

@Test
func dashboardContentResolverServesAssetsAndSpaFallback() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let assetsDirectory = tempRoot.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

    try Data("<!doctype html><html><body>Sloppy</body></html>".utf8)
        .write(to: tempRoot.appendingPathComponent("index.html"))
    try Data("console.log('dashboard');".utf8)
        .write(to: assetsDirectory.appendingPathComponent("app.js"))

    let resolver = DashboardContentResolver(
        rootURL: tempRoot,
        templateConfigURL: nil,
        apiBase: "http://127.0.0.1:25101"
    )

    let rootResponse = resolver.response(for: "GET", uri: "/")
    let assetResponse = resolver.response(for: "GET", uri: "/assets/app.js")
    let spaResponse = resolver.response(for: "GET", uri: "/projects/alpha")
    let missingAssetResponse = resolver.response(for: "GET", uri: "/assets/missing.js")

    #expect(rootResponse.status == 200)
    #expect(String(data: rootResponse.body, encoding: .utf8)?.contains("Sloppy") == true)
    #expect(rootResponse.contentType == "text/html; charset=utf-8")

    #expect(assetResponse.status == 200)
    #expect(String(data: assetResponse.body, encoding: .utf8)?.contains("dashboard") == true)
    #expect(assetResponse.contentType == "application/javascript; charset=utf-8")

    #expect(spaResponse.status == 200)
    #expect(String(data: spaResponse.body, encoding: .utf8)?.contains("Sloppy") == true)

    #expect(missingAssetResponse.status == 404)
}

@Test
func dashboardBundleResolverPrefersInstalledBundle() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let homeURL = tempRoot.appendingPathComponent("home", isDirectory: true)
    let sourceRepoRoot = tempRoot.appendingPathComponent("source-repo", isDirectory: true)
    try createDashboardBundle(at: defaultInstalledDashboardRootURL(homeDirectoryURL: homeURL))
    try createCheckoutDashboard(at: sourceRepoRoot)

    let resolution = resolveDashboardBundle(
        overridePath: nil,
        executableURL: nil,
        sourceRepoRootURL: sourceRepoRoot,
        homeDirectoryURL: homeURL
    )

    #expect(resolution.location?.source == "installed bundle")
    #expect(resolution.location?.distRootURL.path == defaultInstalledDashboardRootURL(homeDirectoryURL: homeURL).appendingPathComponent("dist", isDirectory: true).path)
}

@Test
func dashboardBundleResolverUsesExecutableCheckoutWhenAvailable() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let repoRoot = tempRoot.appendingPathComponent("repo", isDirectory: true)
    try createCheckoutDashboard(at: repoRoot)

    let executableURL = repoRoot
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("apple", isDirectory: true)
        .appendingPathComponent("Products", isDirectory: true)
        .appendingPathComponent("Release", isDirectory: true)
        .appendingPathComponent("sloppy")

    let resolution = resolveDashboardBundle(
        overridePath: nil,
        executableURL: executableURL,
        sourceRepoRootURL: tempRoot.appendingPathComponent("missing-source", isDirectory: true),
        homeDirectoryURL: tempRoot.appendingPathComponent("home", isDirectory: true)
    )

    #expect(resolution.location?.source == "executable checkout")
    #expect(resolution.location?.distRootURL.path == repoRoot.appendingPathComponent("Dashboard", isDirectory: true).appendingPathComponent("dist", isDirectory: true).path)
}

@Test
func dashboardBundleResolverFallsBackToSourceCheckout() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let sourceRepoRoot = tempRoot.appendingPathComponent("source-repo", isDirectory: true)
    try createCheckoutDashboard(at: sourceRepoRoot)

    let resolution = resolveDashboardBundle(
        overridePath: nil,
        executableURL: nil,
        sourceRepoRootURL: sourceRepoRoot,
        homeDirectoryURL: tempRoot.appendingPathComponent("home", isDirectory: true)
    )

    #expect(resolution.location?.source == "source fallback")
}

@Test
func dashboardBundleSearchSummaryListsCheckedPaths() throws {
    let tempRoot = try makeDashboardFixture()
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let overrideURL = tempRoot.appendingPathComponent("override", isDirectory: true)
    let resolution = resolveDashboardBundle(
        overridePath: overrideURL.path,
        executableURL: tempRoot.appendingPathComponent("missing-sloppy"),
        sourceRepoRootURL: tempRoot.appendingPathComponent("missing-source", isDirectory: true),
        homeDirectoryURL: tempRoot.appendingPathComponent("home", isDirectory: true)
    )

    #expect(resolution.location == nil)
    let summary = dashboardBundleSearchSummary(resolution.attempts)
    #expect(summary.contains("override:"))
    #expect(summary.contains("installed bundle:"))
    #expect(summary.contains("source fallback:"))
}

@Test
func viteDashboardPathsResolveFromConfigLocationInsteadOfCurrentWorkingDirectory() throws {
    let repoRoot = repositoryRootURL()
    let vitePathsURL = repoRoot
        .appendingPathComponent("Dashboard", isDirectory: true)
        .appendingPathComponent("vite.paths.js")

    let script = """
    import { resolveDashboardPaths } from \(jsonStringLiteral(vitePathsURL.absoluteString));
    console.log(JSON.stringify(resolveDashboardPaths("file:///virtual/repo/Dashboard/vite.config.js")));
    """

    let output = try runNode(script: script, currentDirectoryURL: repoRoot)
    let data = try #require(output.data(using: .utf8))
    let decoded = try JSONDecoder().decode(ViteDashboardPaths.self, from: data)

    #expect(decoded.dashboardDir == "/virtual/repo/Dashboard")
    #expect(decoded.packageJsonPath == "/virtual/repo/Dashboard/package.json")
    #expect(decoded.dashboardConfigPath == "/virtual/repo/Dashboard/config.json")
    #expect(decoded.distDir == "/virtual/repo/Dashboard/dist")
}

@Test
func dashboardPackageScriptsUseExplicitNodeEntryPointForVite() throws {
    let repoRoot = repositoryRootURL()
    let packageJSONURL = repoRoot
        .appendingPathComponent("Dashboard", isDirectory: true)
        .appendingPathComponent("package.json")
    let data = try Data(contentsOf: packageJSONURL)
    let manifest = try JSONDecoder().decode(DashboardPackageManifest.self, from: data)

    #expect(manifest.scripts["dev"] == "node ./node_modules/vite/bin/vite.js")
    #expect(manifest.scripts["build"] == "node ./node_modules/vite/bin/vite.js build")
    #expect(manifest.scripts["preview"] == "node ./node_modules/vite/bin/vite.js preview")
}

private func makeDashboardFixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func createDashboardBundle(at supportRoot: URL) throws {
    let distRoot = supportRoot.appendingPathComponent("dist", isDirectory: true)
    let assetsRoot = distRoot.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsRoot, withIntermediateDirectories: true)
    try Data("<!doctype html><html><body>Sloppy</body></html>".utf8)
        .write(to: distRoot.appendingPathComponent("index.html"))
    try Data("console.log('dashboard');".utf8)
        .write(to: assetsRoot.appendingPathComponent("app.js"))
    try Data("{\"apiBase\":\"http://localhost:25101\"}".utf8)
        .write(to: supportRoot.appendingPathComponent("config.json"))
}

private func createCheckoutDashboard(at repoRoot: URL) throws {
    let dashboardRoot = repoRoot.appendingPathComponent("Dashboard", isDirectory: true)
    try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)
    try Data("// package".utf8).write(to: repoRoot.appendingPathComponent("Package.swift"))
    try createDashboardBundle(at: dashboardRoot)
    try Data("{\"name\":\"dashboard\"}".utf8).write(to: dashboardRoot.appendingPathComponent("package.json"))
}

private struct ViteDashboardPaths: Decodable {
    let dashboardDir: String
    let packageJsonPath: String
    let dashboardConfigPath: String
    let distDir: String
}

private struct DashboardPackageManifest: Decodable {
    let scripts: [String: String]
}

private func repositoryRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func runNode(script: String, currentDirectoryURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--input-type=module", "--eval", script]
    process.currentDirectoryURL = currentDirectoryURL

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "RunCommandDashboardTests.Node",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output]
        )
    }

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func jsonStringLiteral(_ string: String) -> String {
    let encoded = try? JSONEncoder().encode(string)
    return String(data: encoded ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
}
