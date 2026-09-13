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
    let capabilities: Set<String> = ["list_pull_requests", "read_details", "read_comments", "read_diff"]

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
        case invalidReviewID
        case invalidResponse
        case githubHTTP(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Connect a GitHub account to load pull requests."
            case .invalidReviewID:
                return "The GitHub pull request identifier is invalid."
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

    func codeReviewDetail(id reviewID: String, maxDiffBytes: Int, credential: String?) async throws -> CodeReviewDetail {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ProviderError.missingToken
        }
        let reference = try parseReviewID(reviewID)
        let pullPath = "/repos/\(reference.repository)/pulls/\(reference.number)"

        let pullData = try await request(path: pullPath, token: token)
        async let reviewCommentsResponse = capturedRequest(
            path: "\(pullPath)/comments?per_page=100",
            token: token
        )
        async let issueCommentsResponse = capturedRequest(
            path: "/repos/\(reference.repository)/issues/\(reference.number)/comments?per_page=100",
            token: token
        )
        async let reviewsResponse = capturedRequest(
            path: "\(pullPath)/reviews?per_page=100",
            token: token
        )
        async let diffResponse = capturedRequest(
            path: pullPath,
            token: token,
            accept: "application/vnd.github.v3.diff"
        )

        let (reviewCommentsResult, issueCommentsResult, reviewsResult, diffResult) = await (
            reviewCommentsResponse,
            issueCommentsResponse,
            reviewsResponse,
            diffResponse
        )
        guard let pull = try JSONSerialization.jsonObject(with: pullData) as? [String: Any],
              let item = parsePullRequest(pull, repository: reference.repository, reviewID: reviewID) else {
            throw ProviderError.invalidResponse
        }

        var comments: [CodeReviewComment] = []
        var commentErrors: [String] = []
        appendComments(from: reviewCommentsResult, parser: parseReviewComments, to: &comments, errors: &commentErrors)
        appendComments(from: issueCommentsResult, parser: parseIssueComments, to: &comments, errors: &commentErrors)
        appendComments(from: reviewsResult, parser: parseReviews, to: &comments, errors: &commentErrors)
        comments.sort {
            ($0.createdAt ?? $0.updatedAt ?? .distantPast)
                < ($1.createdAt ?? $1.updatedAt ?? .distantPast)
        }

        let diffLimit = max(1, maxDiffBytes)
        let diff: String
        let diffTruncated: Bool
        let diffError: String?
        switch diffResult {
        case .success(let rawDiffData):
            diff = String(decoding: rawDiffData.prefix(diffLimit), as: UTF8.self)
            diffTruncated = rawDiffData.count > diffLimit
            diffError = nil
        case .failure(let error):
            diff = ""
            diffTruncated = false
            diffError = error.localizedDescription
        }

        return CodeReviewDetail(
            item: item,
            description: pull["body"] as? String,
            sourceBranch: (pull["head"] as? [String: Any])?["ref"] as? String,
            targetBranch: (pull["base"] as? [String: Any])?["ref"] as? String,
            reviewers: reviewerNames(pull),
            comments: comments,
            commentsError: commentErrors.isEmpty ? nil : commentErrors.joined(separator: "\n"),
            diff: diff,
            diffTruncated: diffTruncated,
            diffError: diffError
        )
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

    private func request(
        path: String,
        token: String,
        accept: String = "application/vnd.github+json"
    ) async throws -> Data {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw ProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("sloppy-core", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.githubHTTP(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private func capturedRequest(
        path: String,
        token: String,
        accept: String = "application/vnd.github+json"
    ) async -> Result<Data, Error> {
        do {
            return .success(try await request(path: path, token: token, accept: accept))
        } catch {
            return .failure(error)
        }
    }

    private func appendComments(
        from result: Result<Data, Error>,
        parser: (Data) throws -> [CodeReviewComment],
        to comments: inout [CodeReviewComment],
        errors: inout [String]
    ) {
        do {
            comments.append(contentsOf: try parser(result.get()))
        } catch {
            errors.append(error.localizedDescription)
        }
    }

    private func parseReviewID(_ reviewID: String) throws -> (repository: String, number: Int) {
        let value = reviewID.hasPrefix("github:") ? String(reviewID.dropFirst("github:".count)) : reviewID
        guard let separator = value.lastIndex(of: "#"),
              let number = Int(value[value.index(after: separator)...]) else {
            throw ProviderError.invalidReviewID
        }
        let repository = String(value[..<separator])
        guard repository.split(separator: "/").count == 2 else {
            throw ProviderError.invalidReviewID
        }
        return (repository, number)
    }

    private func parsePullRequest(
        _ object: [String: Any],
        repository: String,
        reviewID: String
    ) -> CodeReviewItem? {
        guard let title = object["title"] as? String,
              let url = object["html_url"] as? String else {
            return nil
        }
        let number = (object["number"] as? NSNumber)?.intValue
        let rawState = (object["state"] as? String)?.lowercased()
        let merged = object["merged_at"] is String
        let state: CodeReviewState = merged ? .merged : (rawState == "closed" ? .closed : .open)
        let author = (object["user"] as? [String: Any])?["login"] as? String
        let labels = (object["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        return CodeReviewItem(
            id: reviewID,
            providerId: id,
            providerName: displayName,
            repository: repository,
            number: number,
            title: title,
            url: url,
            author: author,
            state: state,
            isDraft: object["draft"] as? Bool ?? false,
            roles: [],
            reviewDecision: nil,
            checksStatus: nil,
            labels: labels,
            createdAt: parseDate(object["created_at"] as? String),
            updatedAt: parseDate(object["updated_at"] as? String)
        )
    }

    private func reviewerNames(_ object: [String: Any]) -> [String] {
        let users = (object["requested_reviewers"] as? [[String: Any]])?.compactMap {
            $0["login"] as? String
        } ?? []
        let teams = (object["requested_teams"] as? [[String: Any]])?.compactMap {
            $0["name"] as? String ?? $0["slug"] as? String
        } ?? []
        return users + teams
    }

    private func parseReviewComments(_ data: Data) throws -> [CodeReviewComment] {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.invalidResponse
        }
        return values.compactMap { value in
            guard let identifier = (value["id"] as? NSNumber)?.stringValue,
                  let body = value["body"] as? String else { return nil }
            return CodeReviewComment(
                id: "github-review-comment-\(identifier)",
                author: (value["user"] as? [String: Any])?["login"] as? String,
                body: body,
                filePath: value["path"] as? String,
                line: (value["line"] as? NSNumber)?.intValue,
                originalLine: (value["original_line"] as? NSNumber)?.intValue,
                side: value["side"] as? String,
                diffHunk: value["diff_hunk"] as? String,
                inReplyToId: (value["in_reply_to_id"] as? NSNumber).map { "github-review-comment-\($0)" },
                isResolved: nil,
                isOutdated: value["line"] is NSNull,
                status: "open",
                createdAt: parseDate(value["created_at"] as? String),
                updatedAt: parseDate(value["updated_at"] as? String)
            )
        }
    }

    private func parseIssueComments(_ data: Data) throws -> [CodeReviewComment] {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.invalidResponse
        }
        return values.compactMap { value in
            guard let identifier = (value["id"] as? NSNumber)?.stringValue,
                  let body = value["body"] as? String else { return nil }
            return CodeReviewComment(
                id: "github-issue-comment-\(identifier)",
                author: (value["user"] as? [String: Any])?["login"] as? String,
                body: body,
                createdAt: parseDate(value["created_at"] as? String),
                updatedAt: parseDate(value["updated_at"] as? String)
            )
        }
    }

    private func parseReviews(_ data: Data) throws -> [CodeReviewComment] {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.invalidResponse
        }
        return values.compactMap { value in
            guard let identifier = (value["id"] as? NSNumber)?.stringValue,
                  let body = value["body"] as? String,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return CodeReviewComment(
                id: "github-review-\(identifier)",
                author: (value["user"] as? [String: Any])?["login"] as? String,
                body: body,
                status: (value["state"] as? String)?.lowercased(),
                createdAt: parseDate(value["submitted_at"] as? String)
            )
        }
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
