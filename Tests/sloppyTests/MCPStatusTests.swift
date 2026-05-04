import Testing
@testable import sloppy

@Test("MCP status reports disabled and invalid servers")
func mcpServerStatusesReportDisabledAndInvalidServers() async {
    let registry = MCPClientRegistry(
        config: CoreConfig.MCP(
            servers: [
                .init(id: "off", enabled: false),
                .init(id: "bad-stdio", transport: .stdio, command: nil)
            ]
        )
    )

    let statuses = await registry.serverStatuses()

    #expect(statuses.count == 2)
    #expect(statuses[0].id == "off")
    #expect(statuses[0].enabled == false)
    #expect(statuses[0].connected == false)
    #expect(statuses[0].message == "disabled")

    #expect(statuses[1].id == "bad-stdio")
    #expect(statuses[1].enabled)
    #expect(statuses[1].connected == false)
    #expect(statuses[1].message?.contains("command is missing") == true)
}

@Test("CoreService exposes MCP runtime statuses")
func coreServiceExposesMCPRuntimeStatuses() async {
    var config = CoreConfig.test
    config.mcp = CoreConfig.MCP(
        servers: [
            .init(id: "off", enabled: false)
        ]
    )
    let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())

    let statuses = await service.listMCPServerStatuses()

    #expect(statuses.count == 1)
    #expect(statuses[0].id == "off")
    #expect(statuses[0].message == "disabled")
}
