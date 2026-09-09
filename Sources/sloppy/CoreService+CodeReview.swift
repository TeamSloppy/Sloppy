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
}
