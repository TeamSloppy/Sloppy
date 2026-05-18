import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Test
func sourceControlProvidersEndpointListsBuiltinGitProvider() async throws {
    let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "GET", path: "/v1/source-control/providers", body: nil)
    #expect(response.status == 200)

    let providers = try JSONDecoder().decode([SourceControlProviderRecord].self, from: response.body)
    let gitProvider = try #require(providers.first(where: { $0.id == "git-cli" }))
    #expect(gitProvider.displayName == "Git CLI")
    #expect(gitProvider.capabilities.contains("worktrees"))
    #expect(gitProvider.capabilities.contains("branch_diff"))
}
