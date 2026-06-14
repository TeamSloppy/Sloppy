import Foundation
import Testing
@testable import sloppy

@Test
func coffeeStatusRunsPmsetInspectionCommands() throws {
    let runner = RecordingCoffeeSystemCommandRunner(results: [
        .init(exitCode: 0, stdout: "PreventUserIdleSystemSleep 1", stderr: ""),
        .init(exitCode: 0, stdout: "AC Power:\n sleep 0\n disablesleep 1", stderr: ""),
    ])
    let service = CoffeeSystemService(
        runner: runner,
        platform: .macOS,
        isRoot: { false },
        fileManager: .default
    )

    let status = try service.status(config: .init(enabled: true), workspaceRoot: temporaryCoffeeWorkspace())

    #expect(runner.commands == [
        ["/usr/bin/pmset", "-g", "assertions"],
        ["/usr/bin/pmset", "-g", "custom"],
    ])
    #expect(status.privilegedLidModeActive == true)
    #expect(status.assertionsOutput.contains("PreventUserIdleSystemSleep"))
}

@Test
func coffeeStatusReportsUnsupportedPlatformWithoutPmset() throws {
    let runner = RecordingCoffeeSystemCommandRunner()
    let service = CoffeeSystemService(
        runner: runner,
        platform: .linux,
        isRoot: { false },
        fileManager: .default
    )

    let status = try service.status(config: .init(enabled: true), workspaceRoot: temporaryCoffeeWorkspace())

    #expect(runner.commands.isEmpty)
    #expect(status.assertionsOutput == "Coffee Mode power inspection is only available on macOS.")
    #expect(status.privilegedLidModeActive == false)
}

@Test
func coffeeApplyRequiresExplicitUnsupportedFlag() throws {
    let service = CoffeeSystemService(
        runner: RecordingCoffeeSystemCommandRunner(),
        platform: .macOS,
        isRoot: { true },
        fileManager: .default
    )

    #expect(throws: CoffeeSystemServiceError.unsupportedLidModeNotAllowed) {
        try service.applyPrivilegedLidMode(
            allowUnsupportedLidMode: false,
            workspaceRoot: temporaryCoffeeWorkspace()
        )
    }
}

@Test
func coffeeApplyRequiresRoot() throws {
    let service = CoffeeSystemService(
        runner: RecordingCoffeeSystemCommandRunner(),
        platform: .macOS,
        isRoot: { false },
        fileManager: .default
    )

    #expect(throws: CoffeeSystemServiceError.requiresRoot) {
        try service.applyPrivilegedLidMode(
            allowUnsupportedLidMode: true,
            workspaceRoot: temporaryCoffeeWorkspace()
        )
    }
}

@Test
func coffeeApplyRunsDisableSleepAndWritesState() throws {
    let runner = RecordingCoffeeSystemCommandRunner(results: [
        .init(exitCode: 0, stdout: "ok", stderr: ""),
    ])
    let workspace = try temporaryCoffeeWorkspace()
    let service = CoffeeSystemService(
        runner: runner,
        platform: .macOS,
        isRoot: { true },
        fileManager: .default
    )

    try service.applyPrivilegedLidMode(allowUnsupportedLidMode: true, workspaceRoot: workspace)

    #expect(runner.commands == [["/usr/bin/pmset", "-a", "disablesleep", "1"]])
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("coffee-mode-state.json").path))
}

@Test
func coffeeRevertRunsDisableSleepOff() throws {
    let runner = RecordingCoffeeSystemCommandRunner(results: [
        .init(exitCode: 0, stdout: "ok", stderr: ""),
    ])
    let service = CoffeeSystemService(
        runner: runner,
        platform: .macOS,
        isRoot: { true },
        fileManager: .default
    )

    try service.revertPrivilegedLidMode(workspaceRoot: temporaryCoffeeWorkspace())

    #expect(runner.commands == [["/usr/bin/pmset", "-a", "disablesleep", "0"]])
}

private final class RecordingCoffeeSystemCommandRunner: CoffeeSystemCommandRunning {
    var commands: [[String]] = []
    private var results: [CoffeeSystemCommandResult]

    init(results: [CoffeeSystemCommandResult] = []) {
        self.results = results
    }

    func run(_ command: [String]) throws -> CoffeeSystemCommandResult {
        commands.append(command)
        if results.isEmpty {
            return .init(exitCode: 0, stdout: "", stderr: "")
        }
        return results.removeFirst()
    }
}

private func temporaryCoffeeWorkspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-coffee-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
