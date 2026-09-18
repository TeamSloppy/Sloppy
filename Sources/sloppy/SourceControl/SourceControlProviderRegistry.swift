import Foundation
import Protocols
import PluginSDK

extension CoreService {
    static let defaultSourceControlProviderID = "git-cli"

    func sourceControlProvider(id requestedId: String? = nil) -> any SourceControlProvider {
        if let requestedId,
           let provider = sourceControlProviders[requestedId] {
            return provider
        }
        if let provider = sourceControlProviders[Self.defaultSourceControlProviderID] {
            return provider
        }
        let fallback = GitCLISourceControlProvider(service: gitWorktreeService)
        sourceControlProviders[fallback.id] = fallback
        return fallback
    }

    func sourceControlProvider(for project: ProjectRecord, task: ProjectTask? = nil) -> any SourceControlProvider {
        sourceControlProvider(id: task?.sourceControlProviderId ?? project.sourceControlProviderId)
    }

    func inspectSourceControlProvider(
        for project: ProjectRecord,
        task: ProjectTask? = nil,
        at path: String
    ) async -> (provider: any SourceControlProvider, repository: SourceControlRepositoryInfo) {
        if let requestedID = task?.sourceControlProviderId ?? project.sourceControlProviderId {
            let provider = sourceControlProvider(id: requestedID)
            let repository = await provider.inspectRepository(at: path)
            if repository.isRepository || requestedID != Self.defaultSourceControlProviderID {
                return (provider, repository)
            }
        }

        let fallback = sourceControlProvider()
        let fallbackRepository = await fallback.inspectRepository(at: path)
        if fallbackRepository.isRepository {
            return (fallback, fallbackRepository)
        }

        for provider in sourceControlProviders.values
            .filter({ $0.id != fallback.id })
            .sorted(by: { $0.id < $1.id }) {
            let repository = await provider.inspectRepository(at: path)
            if repository.isRepository {
                return (provider, repository)
            }
        }
        return (fallback, fallbackRepository)
    }

    func registerSourceControlProvider(_ provider: any SourceControlProvider) {
        sourceControlProviders[provider.id] = provider
    }

    public func listSourceControlProviders() async -> [SourceControlProviderRecord] {
        sourceControlProviders.values
            .map { provider in
                SourceControlProviderRecord(
                    id: provider.id,
                    displayName: provider.displayName,
                    capabilities: provider.capabilities.map(\.rawValue).sorted()
                )
            }
            .sorted { $0.id < $1.id }
    }
}
