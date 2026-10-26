import Foundation

extension SloppyAPIClient {
    public func searchText(_ query: String, mode: TextSearchMode = .text, offset: Int = 0) async throws -> TextSearchResponse {
        var parameters = URLComponents()
        parameters.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "limit", value: "50")]
        return try await http.get("/v1/search?" + (parameters.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B"), timeout: 5)
    }

    public func fetchSearchDocument(id: String) async throws -> TextSearchDocumentResponse {
        var parameters = URLComponents()
        parameters.queryItems = [URLQueryItem(name: "id", value: id)]
        return try await http.get("/v1/search/document?" + (parameters.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B"))
    }
}
