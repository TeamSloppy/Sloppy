import Testing
@testable import sloppy

@Suite struct SloppyCLIParsingTests {
    @Test func serverReceivesItsConfigOption() throws {
        let command = try #require(SloppyApp.parseCommand(["run", "--config-path", "custom.json", "--no-gui"]) as? RunCommand)
        #expect(command.configPath == "custom.json")
        #expect(command.gui == false)
    }

    @Test func tuiReceivesItsConfigAndSessionOptions() throws {
        let command = try #require(SloppyApp.parseCommand(["tui", "--config-path", "custom.json", "--session", "session-1"]) as? TuiCommand)
        #expect(command.configPath == "custom.json")
        #expect(command.session == "session-1")
    }

    @Test func rootPromptRetainsItsOptions() throws {
        let command = try #require(SloppyApp.parseCommand(["-p", "hello", "--config-path", "custom.json", "--agent", "agent-1"]) as? SloppyApp)
        #expect(command.prompt == "hello")
        #expect(command.configPath == "custom.json")
        #expect(command.agent == "agent-1")
    }
}
