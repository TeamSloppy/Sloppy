import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PluginSDK
import Protocols

struct GitHubCodeReviewProvider: CodeReviewProvider {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    let id = "github"
    let displayName = "GitHub"
    let capabilities: Set<String> = ["list_pull_requests"]

    private let tokenProvider: @Sendable () -> String?
    private let transport: Transport

    init(
        tokenProvider: @escaping @Sendable () -> String?,
        transport: Transport? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport ?? { request in
            let (data, response) = try await SloppyURLSessionFactory.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }
    }

    enum ProviderError: LocalizedError {
        case missingToken
        case invalidResponse
        case githubHTTP(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Connect a GitHub account to load pull requests."
            case .invalidResponse:
                return "GitHub returned an invalid pull request response."
            case .githubHTTP(let status, let body):
                return "GitHub API failed with HTTP \(status): \(body)"
            }
        }
    }

    func listCodeReviews(query: CodeReviewQuery) async throws -> [CodeReviewItem] {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ProviderError.missingToken
        }

        let roles = query.roles.isEmpty ? CodeReviewRole.allCases : query.roles
        var itemsByID: [String: CodeReviewItem] = [:]
        for role in roles {
            let items = try await search(role: role, query: query, token: token)
            for item in items {
                if var existing = itemsByID[item.id] {
                    existing.roles = Array(Set(existing.roles + item.roles)).sorted { $0.rawValue < $1.rawValue }
                    itemsByID[item.id] = existing
                } else {
                    itemsByID[item.id] = item
                }
            }
        }

        return itemsByID.values
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .prefix(query.limit)
            .map { $0 }
    }

    private func search(
        role: CodeReviewRole,
        query: CodeReviewQuery,
        token: String
    ) async throws -> [CodeReviewItem] {
        let roleQualifier = switch role {
        case .authored: "author:@me"
        case .reviewRequested: "review-requested:@me"
        }
        let stateQualifier = switch query.state {
        case .open: "is:open"
        case .closed: "is:closed -is:merged"
        case .merged: "is:merged"
        case .all: ""
        }
        let searchQuery = ["is:pr", stateQualifier, roleQualifier]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: String(min(query.limit, 100))),
        ]
        guard let url = components.url else { throw ProviderError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("sloppy-core", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.githubHTTP(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = object["items"] as? [[String: Any]] else {
            throw ProviderError.invalidResponse
        }
        return rawItems.compactMap { parse($0, role: role) }
    }

    private func parse(_ object: [String: Any], role: CodeReviewRole) -> CodeReviewItem? {
        guard let title = object["title"] as? String,
              let url = object["html_url"] as? String,
              let repositoryURL = object["repository_url"] as? String else {
            return nil
        }
        let repository = repositoryURL
            .components(separatedBy: "/repos/")
            .last ?? repositoryURL
        let number = (object["number"] as? NSNumber)?.intValue
        let pullRequest = object["pull_request"] as? [String: Any]
        let merged = pullRequest?["merged_at"] is String
        let rawState = (object["state"] as? String)?.lowercased()
        let state: CodeReviewState = merged ? .merged : (rawState == "closed" ? .closed : .open)
        let author = (object["user"] as? [String: Any])?["login"] as? String
        let labels = (object["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let stableID = "github:\(repository)#\(number.map(String.init) ?? url)"

        return CodeReviewItem(
            id: stableID,
            providerId: id,
            providerName: displayName,
            repository: repository,
            number: number,
            title: title,
            url: url,
            author: author,
            state: state,
            isDraft: object["draft"] as? Bool ?? false,
            roles: [role],
            labels: labels,
            createdAt: parseDate(object["created_at"] as? String),
            updatedAt: parseDate(object["updated_at"] as? String)
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
