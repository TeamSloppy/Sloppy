import Protocols

/// Optional provider capability used by the global Pull Requests inbox.
///
/// Providers own their service credentials. Sloppy aggregates every registered
/// provider so clients never need service-specific API knowledge.
public protocol CodeReviewProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: Set<String> { get }

    func listCodeReviews(query: CodeReviewQuery) async throws -> [CodeReviewItem]
}

public extension CodeReviewProvider {
    var displayName: String { id }
    var capabilities: Set<String> { ["list_pull_requests"] }
}
