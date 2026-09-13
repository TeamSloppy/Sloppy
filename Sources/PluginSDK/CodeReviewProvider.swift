import Foundation
import Protocols

public enum CodeReviewProviderError: Error, LocalizedError, Sendable {
    case unsupportedOperation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "This provider does not support \(operation)."
        }
    }
}

/// Optional provider capability used by the global Pull Requests inbox.
///
/// Providers own their service credentials. Sloppy aggregates every registered
/// provider so clients never need service-specific API knowledge.
public protocol CodeReviewProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: Set<String> { get }

    func listCodeReviews(query: CodeReviewQuery) async throws -> [CodeReviewItem]
    func codeReviewDetail(id: String, maxDiffBytes: Int, credential: String?) async throws -> CodeReviewDetail
    func replyToCodeReviewComment(reviewID: String, parentCommentID: String, body: String, credential: String?) async throws -> CodeReviewComment
}

public extension CodeReviewProvider {
    var displayName: String { id }
    var capabilities: Set<String> { ["list_pull_requests"] }

    func codeReviewDetail(id: String, maxDiffBytes: Int, credential: String?) async throws -> CodeReviewDetail {
        throw CodeReviewProviderError.unsupportedOperation("code-review details")
    }

    func replyToCodeReviewComment(reviewID: String, parentCommentID: String, body: String, credential: String?) async throws -> CodeReviewComment {
        throw CodeReviewProviderError.unsupportedOperation("comment replies")
    }
}
