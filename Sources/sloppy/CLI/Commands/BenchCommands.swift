import ArgumentParser
import Foundation
import Protocols

struct BenchCommand: SloppyGroupCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Run agent benchmark suites in disposable sandboxes.",
        subcommands: [BenchListCommand.self, BenchRunCommand.self, BenchMemoryCommand.self, BenchReportCommand.self]
    )
}

private let defaultSuitesPath = "bench/suites"

struct BenchListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List tasks in a suite.")
    @Option(name: .long, help: "Suite name under --suites-dir") var suite: String = "smoke"
    @Option(name: .long, help: "Directory holding suites") var suitesDir: String = defaultSuitesPath

    mutating func run() async throws {
        let tasks = try BenchTaskLoader.loadSuite(at: URL(fileURLWithPath: suitesDir).appendingPathComponent(suite))
        for task in tasks {
            print("\(task.id)\t[\(task.spec.tags.joined(separator: ","))]\t\(task.spec.title)")
        }
    }
}

struct BenchRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a suite against a running Core and report pass rate, steps and tokens."
    )
    @Option(name: .long, help: "Suite name under --suites-dir") var suite: String = "smoke"
    @Option(name: .long, help: "Directory holding suites") var suitesDir: String = defaultSuitesPath
    @Option(name: .customLong("agent-id"), help: "Agent ID that executes the tasks") var agent: String
    @Option(name: .long, help: "Model ID for the turn (default: the agent's model)") var model: String?
    @Option(name: .long, help: "Chat mode: ask, build, plan, debug, auto") var mode: String = "auto"
    @Option(name: [.customShort("n"), .long], help: "Attempts per task") var attempts: Int = 1
    @Option(name: .long, help: "Parallel runs") var concurrency: Int = 2
    @Option(name: .long, help: "Only these task ids or tags (repeatable)") var only: [String] = []
    @Option(name: .long, help: "Write the JSON report here") var output: String?
    @Option(name: .long, help: "Compare against a previous JSON report") var baseline: String?
    @Flag(name: .long, help: "Keep sandbox directories for inspection") var keepSandboxes: Bool = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        guard let chatMode = AgentChatMode(rawValue: mode) else {
            throw ValidationError("Unknown mode '\(mode)'. Use one of: \(AgentChatMode.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let suiteURL = URL(fileURLWithPath: suitesDir).appendingPathComponent(suite)
        let tasks = try BenchTaskLoader.loadSuite(at: suiteURL, filter: Set(only))
        guard !tasks.isEmpty else { throw ValidationError("No tasks matched in \(suiteURL.path).") }

        var client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        client.requestTimeout = 3600
        let runner = BenchRunner(
            driver: BenchHTTPDriver(client: client, agentID: agent),
            configuration: BenchRunConfiguration(
                model: model, mode: chatMode, attempts: attempts, concurrency: concurrency,
                keepSandboxes: keepSandboxes
            ),
            onResult: { result in
                print("\(result.passed ? "PASS" : result.status.rawValue.uppercased())  \(result.taskId) #\(result.attempt)  \(String(format: "%.1fs", result.agentSeconds))\(result.error.map { "  " + $0 } ?? "")")
            }
        )
        let results = await runner.run(tasks: tasks)
        let report = BenchReport(generatedAt: Date(), suite: suite, results: results)
        print("\n" + report.renderTable())
        if let baseline {
            print("\nvs baseline:\n" + report.renderComparison(against: try BenchReport.load(from: URL(fileURLWithPath: baseline))))
        }
        if let output {
            try report.jsonData().write(to: URL(fileURLWithPath: output))
            print("\nReport written to \(output)")
        }
        if results.contains(where: { !$0.passed }) { throw ExitCode(1) }
    }
}

struct BenchReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "report", abstract: "Print a saved JSON report.")
    @Argument(help: "Report JSON file") var file: String
    @Option(name: .long, help: "Compare against a previous report") var baseline: String?

    mutating func run() async throws {
        let report = try BenchReport.load(from: URL(fileURLWithPath: file))
        print(report.renderTable())
        if let baseline {
            print("\nvs baseline:\n" + report.renderComparison(against: try BenchReport.load(from: URL(fileURLWithPath: baseline))))
        }
    }
}

struct BenchMemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Run multi-session memory scenarios: teach facts, then check a fresh session uses them."
    )
    @Option(name: .long, help: "Directory with scenario .json files") var dir: String = "bench/memory"
    @Option(name: .long, help: "Model ID for every turn (default: the agent's model)") var model: String?
    @Option(name: .long, help: "Chat mode: ask, build, plan, debug, auto") var mode: String = "auto"
    @Option(name: [.customShort("n"), .long], help: "Attempts per scenario") var attempts: Int = 1
    @Option(name: .long, help: "Parallel scenarios") var concurrency: Int = 2
    @Option(name: .long, help: "Only these scenario ids or tags (repeatable)") var only: [String] = []
    @Option(name: .long, help: "The Core's data directory (e.g. ~/.sloppy); lets the report say where facts were stored") var dataDir: String?
    @Option(name: .long, help: "Write the JSON report here") var output: String?
    @Option(name: .long, help: "Compare against a previous JSON report") var baseline: String?
    @Flag(name: .long, help: "Keep the throwaway agents for inspection") var keepAgents: Bool = false
    @Flag(name: .long, help: "Leave shared memory on (default: off, so runs cannot see each other's facts)") var sharedMemory: Bool = false
    @Option(name: .long) var url: String?
    @Option(name: .long) var token: String?
    @Flag(name: .long) var verbose: Bool = false

    mutating func run() async throws {
        guard let chatMode = AgentChatMode(rawValue: mode) else {
            throw ValidationError("Unknown mode '\(mode)'. Use one of: \(AgentChatMode.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let scenarios = try BenchScenarioLoader.loadSuite(at: URL(fileURLWithPath: dir), filter: Set(only))
        guard !scenarios.isEmpty else { throw ValidationError("No scenarios matched in \(dir).") }

        var client = SloppyCLIClient.resolve(url: url, token: token, verbose: verbose)
        client.requestTimeout = 3600
        let expandedDataDir = dataDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let runner = BenchScenarioRunner(
            driver: BenchScenarioHTTPDriver(client: client, dataDirectory: expandedDataDir, sharedMemory: sharedMemory),
            configuration: BenchRunConfiguration(
                model: model, mode: chatMode, attempts: attempts, concurrency: concurrency, keepSandboxes: keepAgents
            ),
            onResult: { result in
                print("\(result.passed ? "PASS" : result.status.rawValue.uppercased())  \(result.taskId) #\(result.attempt)  \(String(format: "%.1fs", result.agentSeconds))\(result.error.map { "  " + $0 } ?? "")")
            }
        )
        let results = await runner.run(scenarios: scenarios)
        let report = BenchReport(generatedAt: Date(), suite: "memory", results: results)
        print("\n" + report.renderTable())
        for result in results where !(result.checkOutputTail ?? "").isEmpty {
            print("\n[\(result.taskId) #\(result.attempt)]\n\(result.checkOutputTail ?? "")")
        }
        if let baseline {
            print("\nvs baseline:\n" + report.renderComparison(against: try BenchReport.load(from: URL(fileURLWithPath: baseline))))
        }
        if let output {
            try report.jsonData().write(to: URL(fileURLWithPath: output))
            print("\nReport written to \(output)")
        }
        if results.contains(where: { !$0.passed }) { throw ExitCode(1) }
    }
}
