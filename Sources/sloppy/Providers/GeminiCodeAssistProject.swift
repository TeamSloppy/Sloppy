import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum GeminiCodeAssistProjectResolver {
    static let defaultBaseURL = URL(string: "https://cloudcode-pa.googleapis.com")!
    static let userAgent = "antigravity"
    static let apiClient = "google-cloud-sdk vscode_cloudshelleditor/0.1"
    static let clientMetadataHeader = #"{"ideType":"ANTIGRAVITY","platform":"MACOS","pluginType":"GEMINI"}"#

    static func resolve(
        credentials: GeminiOAuthCredentials,
        preferredProjectID: String? = nil,
        baseURL: URL = defaultBaseURL,
        transport: GeminiOAuthCredentials.Transport? = nil
    ) async throws -> String? {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1internal:loadCodeAssist"))
        request.httpMethod = "POST"
        applyHeaders(to: &request, authorizationHeaderValue: credentials.authorizationHeaderValue, accept: "application/json")

        var payload: [String: Any] = [
            "metadata": clientMetadataObject(),
        ]
        let trimmedProjectID = preferredProjectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedProjectID.isEmpty {
            payload["cloudaicompanionProject"] = trimmedProjectID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let resolvedTransport = transport ?? defaultTransport
        let (data, response) = try await resolvedTransport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiOAuthCredentialsError.codeAssistProjectLoadFailed(
                statusCode: response.statusCode,
                body: GeminiOAuthCredentials.sanitizedPayloadSnippet(data)
            )
        }
        return try parseCompanionProjectID(from: data)
    }

    static func applyHeaders(to request: inout URLRequest, authorizationHeaderValue: String, accept: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(apiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(clientMetadataHeader, forHTTPHeaderField: "Client-Metadata")
    }

    static func clientMetadataObject() -> [String: String] {
        [
            "ideType": "ANTIGRAVITY",
            "platform": platformMetadataValue(),
            "pluginType": "GEMINI",
        ]
    }

    private static func platformMetadataValue() -> String {
        #if os(macOS) && arch(arm64)
        return "DARWIN_ARM64"
        #elseif os(macOS)
        return "DARWIN_AMD64"
        #elseif os(Linux) && arch(arm64)
        return "LINUX_ARM64"
        #elseif os(Linux)
        return "LINUX_AMD64"
        #elseif os(Windows)
        return "WINDOWS_AMD64"
        #else
        return "PLATFORM_UNSPECIFIED"
        #endif
    }

    private static func parseCompanionProjectID(from data: Data) throws -> String? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["cloudaicompanionProject"]
        else {
            return nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let object = value as? [String: Any],
           let id = object["id"] as? String {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func defaultTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await SloppyURLSessionFactory.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}
