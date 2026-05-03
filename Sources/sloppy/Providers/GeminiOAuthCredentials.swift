import Foundation

struct GeminiOAuthCredentials: Sendable {
    static let defaultCredentialsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini", isDirectory: true)
        .appendingPathComponent("oauth_creds.json")

    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiryDate: Date?

    var authorizationHeaderValue: String {
        "\(tokenType.isEmpty ? "Bearer" : tokenType) \(accessToken)"
    }

    static func load(url: URL = defaultCredentialsURL) -> GeminiOAuthCredentials? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(GeminiOAuthCredentials.self, from: data)
    }
}

extension GeminiOAuthCredentials: Decodable {
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiryDate = "expiry_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accessToken = try container.decode(String.self, forKey: .accessToken)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .accessToken,
                in: container,
                debugDescription: "Gemini OAuth access token is empty."
            )
        }

        self.accessToken = accessToken
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Bearer"

        if let value = try? container.decode(Double.self, forKey: .expiryDate) {
            let seconds = value > 10_000_000_000 ? value / 1000 : value
            self.expiryDate = Date(timeIntervalSince1970: seconds)
        } else {
            self.expiryDate = nil
        }
    }
}

enum GeminiAuthCredential: Sendable {
    case oauth(GeminiOAuthCredentials)
    case apiKey(String)
}
