import Protocols

/// Type-erased box returned by Swift code-review plugins through the C ABI.
///
/// A plugin declaring `"protocol": "code_review"` exports
/// `sloppy_code_review_create` and returns a retained box pointer.
public final class AnyCodeReviewProviderBox: CodeReviewProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let capabilities: Set<String>

    private let _listCodeReviews: @Sendable (CodeReviewQuery) async throws -> [CodeReviewItem]

    public init(
        id: String,
        displayName: String? = nil,
        capabilities: Set<String> = ["list_pull_requests"],
        listCodeReviews: @escaping @Sendable (CodeReviewQuery) async throws -> [CodeReviewItem]
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.capabilities = capabilities
        self._listCodeReviews = listCodeReviews
    }

    public convenience init(_ provider: any CodeReviewProvider) {
        self.init(
            id: provider.id,
            displayName: provider.displayName,
            capabilities: provider.capabilities,
            listCodeReviews: { query in
                try await provider.listCodeReviews(query: query)
            }
        )
    }

    public func listCodeReviews(query: CodeReviewQuery) async throws -> [CodeReviewItem] {
        try await _listCodeReviews(query)
    }
}
