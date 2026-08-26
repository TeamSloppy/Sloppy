import Foundation
import Testing

@Suite("Root shell authentication routing")
struct RootShellAuthenticationRoutingSourceTests {
    @Test("server selection is not interrupted by stale authentication requirements")
    func ignoresAuthenticationRequirementsWhileChoosingServer() throws {
        let viewModelSource = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")
        let viewSource = try source("Sources/SloppyClient/Root/RootShellView.swift")

        #expect(viewModelSource.contains("guard acceptsAuthenticationRequirement(for: baseURL) else"))
        #expect(viewModelSource.contains("case .splash, .connectionSetup, .pairing:"))
        #expect(viewModelSource.contains("return false"))
        #expect(viewModelSource.contains("func showConnectionSetup()"))
        #expect(viewSource.contains("onChooseServer: {\n                        rootViewModel.showConnectionSetup()"))
        #expect(!viewSource.contains("onChooseServer: {\n                        rootViewModel.appState = .connectionSetup"))
    }

    @Test("authentication challenge cannot restore an abandoned server after its response arrives")
    func rechecksRoutingAfterChallengeFetch() throws {
        let viewModelSource = try source("Sources/SloppyClient/Root/RootShellViewModel.swift")
        let challengeFetch = try #require(
            viewModelSource.range(of: "challenge = try await apiClient.fetchConnectionAuthChallenge()")
        )
        let postFetchGuard = try #require(
            viewModelSource.range(
                of: "guard acceptsAuthenticationRequirement(for: baseURL) else {",
                range: challengeFetch.upperBound..<viewModelSource.endIndex
            )
        )
        let presentation = try #require(
            viewModelSource.range(
                of: "appState = .authentication(baseURL, challenge, message)",
                range: postFetchGuard.upperBound..<viewModelSource.endIndex
            )
        )

        #expect(postFetchGuard.lowerBound < presentation.lowerBound)
    }

    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
