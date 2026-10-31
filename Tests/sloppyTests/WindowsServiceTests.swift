import Foundation
import Testing
@testable import sloppy
import ArgumentParser

@Suite struct WindowsServiceTests {
    @Test func installPreservesPathsAsSeparateArguments() {
        let arguments = WindowsServiceManager.arguments(
            action: .install,
            scriptPath: "C:/Sloppy files/service.ps1",
            executablePath: "C:/Sloppy's files/sloppy.exe",
            configPath: "C:/settings & data/$config.json"
        )
        #expect(arguments == [
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", "C:/Sloppy files/service.ps1", "-Command", "install",
            "-ExecutablePath", "C:/Sloppy's files/sloppy.exe",
            "-ConfigPath", "C:/settings & data/$config.json",
        ])
    }

    @Test func lifecycleCommandsDoNotReplaceSavedConfiguration() {
        for action in [WindowsServiceManager.Action.start, .stop, .restart, .status, .uninstall] {
            let arguments = WindowsServiceManager.arguments(action: action, scriptPath: "service.ps1")
            #expect(arguments.suffix(2) == ["-Command", action.rawValue])
            #expect(!arguments.contains("-ConfigPath"))
            #expect(!arguments.contains("-ExecutablePath"))
        }
    }

    @Test func serviceLogsForwardsRequestedLineCount() throws {
        let parsed = try #require(SloppyApp.parseCommand(["service", "logs", "--lines", "123"]) as? ServiceLogsCommand)
        let arguments = WindowsServiceManager.arguments(action: .logs, scriptPath: "service.ps1", lines: parsed.lines)
        #expect(arguments.suffix(2) == ["-Lines", "123"])
    }

    @Test func windowsServiceRunnerIsBundled() throws {
        let url = try #require(WindowsServiceManager.scriptURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
