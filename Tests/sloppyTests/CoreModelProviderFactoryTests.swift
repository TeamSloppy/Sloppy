import Foundation
import Testing
@testable import sloppy

@Test
func coreModelProviderFactoryAcceptsOpenRouterPrefixedModel() {
    let model = CoreConfig.ModelConfig(
        title: "openrouter-main",
        apiKey: "",
        apiUrl: "",
        model: "openrouter:anthropic/claude-3.5-sonnet"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:anthropic/claude-3.5-sonnet")
}

@Test
func coreModelProviderFactoryInfersOpenRouterFromApiHost() {
    let model = CoreConfig.ModelConfig(
        title: "edge",
        apiKey: "sk-or-test",
        apiUrl: "https://openrouter.ai/api/v1",
        model: "openai/gpt-4o-mini"
    )
    #expect(CoreModelProviderFactory.resolvedIdentifier(for: model) == "openrouter:openai/gpt-4o-mini")
}

@Test
func geminiOAuthCredentialsLoadReadsGeminiCLIFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gemini-oauth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("oauth_creds.json")
    try Data(
        """
        {
          "access_token": "oauth-token",
          "refresh_token": "refresh-token",
          "token_type": "Bearer",
          "expiry_date": 1893456000000
        }
        """.utf8
    ).write(to: url)

    let credentials = try #require(GeminiOAuthCredentials.load(url: url))
    #expect(credentials.accessToken == "oauth-token")
    #expect(credentials.refreshToken == "refresh-token")
    #expect(credentials.authorizationHeaderValue == "Bearer oauth-token")
}

@Test
func coreModelProviderFactoryBuildsGeminiFromOAuthCredentialsWithoutAPIKey() {
    var config = CoreConfig.test
    config.models = [
        CoreConfig.ModelConfig(
            title: "gemini",
            apiKey: "",
            apiUrl: "https://generativelanguage.googleapis.com",
            model: "gemini-2.5-flash",
            providerCatalogId: "gemini"
        )
    ]
    let provider = CoreModelProviderFactory.buildModelProvider(
        config: config,
        resolvedModels: ["gemini:gemini-2.5-flash"],
        geminiOAuthCredentialsProvider: {
            GeminiOAuthCredentials(
                accessToken: "oauth-token",
                refreshToken: nil,
                tokenType: "Bearer",
                expiryDate: nil
            )
        }
    )

    #expect(provider?.supportedModels == ["gemini:gemini-2.5-flash"])
}

@Test
func geminiOAuthURLProtocolRewritesAPIKeyHeaderToBearerAuth() throws {
    var request = URLRequest(url: try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini:generateContent")))
    request.setValue("oauth-token", forHTTPHeaderField: "x-goog-api-key")

    let modified = GeminiOAuthURLProtocol.modifiedRequest(from: request)

    #expect(modified.value(forHTTPHeaderField: "x-goog-api-key") == nil)
    #expect(modified.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
}

@Test
func sloppyExtraCertificateAuthorityExtractsMultiplePEMCertificates() {
    let first = Data([0x01, 0x02, 0x03]).base64EncodedString()
    let second = Data([0x04, 0x05, 0x06]).base64EncodedString()
    let pem =
        """
        -----BEGIN CERTIFICATE-----
        \(first)
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        \(second)
        -----END CERTIFICATE-----
        """

    let certificates = SloppyExtraCertificateAuthority.certificateData(fromPEM: pem)

    #expect(certificates == [Data([0x01, 0x02, 0x03]), Data([0x04, 0x05, 0x06])])
}
