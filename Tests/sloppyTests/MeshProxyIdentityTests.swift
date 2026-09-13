import Foundation
import Testing
import Protocols
import SloppyNodeCore
@testable import sloppy

@Test
func meshProxyUsesAuthenticatedIdentityForLocalRequests() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = NodeIdentityGenerator.makeIdentity(name: "Local", roles: ["controller"], capabilities: ["sloppy.core.remote"])
    let configStore = NodeConfigStore(configURL: root.appendingPathComponent("node.json"))
    try configStore.save(NodeConfig(identity: identity, relayURL: "http://mesh.example.test"))
    let service = CoreService(config: .test, nodeConfigStore: configStore)
    await service.setIdentityAuthEnabled(true)
    let session = try await service.bootstrapIdentityAdmin(.init(login: "admin", password: "test-password", name: "Admin"))
    let router = CoreRouter(service: service)
    let body = Data(#"{"method":"GET","path":"/v1/auth/me","headers":{"Authorization":"Bearer invalid-inner-token","x-sloppy-user-context":"another-user"}}"#.utf8)
    let response = await router.handle(method: "POST", path: "/v1/node/mesh/nodes/\(identity.nodeId)/core", body: body,
                                       headers: ["Authorization": "Bearer \(session.accessToken)", "x-sloppy-user-context": "spoofed-outer-user"])
    #expect(response.status == 200)
    let object = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    #expect(object["status"] as? Int == 200)
    let bodyBase64 = try #require(object["bodyBase64"] as? String)
    let data = try #require(Data(base64Encoded: bodyBase64))
    let profile = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(profile["id"] as? String == session.user.id)

    let unauthorized = await router.handle(method: "POST", path: "/v1/node/mesh/nodes/\(identity.nodeId)/core", body: body)
    #expect(unauthorized.status == 401)
}
