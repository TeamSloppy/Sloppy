import Foundation
import PluginSDK
import Protocols

extension CoreService {
    func registerCodeReviewProvider(_ provider: any CodeReviewProvider) {
        codeReviewProviders[provider.id] = provider
    }

    public func listCodeReviewProviders() -> [CodeReviewProviderDescriptor] {
        codeReviewProviders.values
            .map {
                CodeReviewProviderDescriptor(
                    id: $0.id,
                    displayName: $0.displayName,
                    capabilities: Array($0.capabilities).sorted()
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func codeReviewInbox(
        query: CodeReviewQuery,
        providerIDs: Set<String> = []
    ) async -> CodeReviewInboxResponse {
        let selected = codeReviewProviders.values
            .filter { providerIDs.isEmpty || providerIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        var items: [CodeReviewItem] = []
        var failures: [String: String] = [:]

        for provider in selected {
            do {
                items.append(contentsOf: try await provider.listCodeReviews(query: query))
            } catch {
                failures[provider.id] = error.localizedDescription
            }
        }

        items.sort {
            ($0.updatedAt ?? $0.createdAt ?? .distantPast)
                > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
        }
        return CodeReviewInboxResponse(
            items: Array(items.prefix(query.limit)),
            providers: listCodeReviewProviders(),
            failures: failures
        )
    }

    public func codeReviewDetail(
        providerID: String,
        reviewID: String,
        maxDiffBytes: Int = 1_048_576
    ) async throws -> CodeReviewDetail {
        guard let provider = codeReviewProviders[providerID] else {
            throw CodeReviewProviderError.unsupportedOperation("unknown provider \(providerID)")
        }
        return try await provider.codeReviewDetail(
            id: reviewID,
            maxDiffBytes: max(1, min(maxDiffBytes, 4 * 1_048_576)),
            credential: codeReviewCredential(providerID: providerID)
        )
    }

    public func replyToCodeReviewComment(
        providerID: String,
        reviewID: String,
        parentCommentID: String,
        body: String
    ) async throws -> CodeReviewComment {
        guard let provider = codeReviewProviders[providerID] else {
            throw CodeReviewProviderError.unsupportedOperation("unknown provider \(providerID)")
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChannelPluginError.invalidPayload }
        return try await provider.replyToCodeReviewComment(
            reviewID: reviewID,
            parentCommentID: parentCommentID,
            body: trimmed,
            credential: codeReviewCredential(providerID: providerID)
        )
    }
}
