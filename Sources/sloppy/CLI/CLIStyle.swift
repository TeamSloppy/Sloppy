import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CLIStyle {
    static let isColor: Bool = {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
            return false
        }
        if let term = ProcessInfo.processInfo.environment["TERM"], term == "dumb" || term.isEmpty {
            return false
        }
        return isatty(STDOUT_FILENO) != 0
    }()

    static func cyan(_ s: String) -> String    { isColor ? "\u{1B}[36m\(s)\u{1B}[0m" : s }
    static func green(_ s: String) -> String   { isColor ? "\u{1B}[32m\(s)\u{1B}[0m" : s }
    static func yellow(_ s: String) -> String  { isColor ? "\u{1B}[33m\(s)\u{1B}[0m" : s }
    static func red(_ s: String) -> String     { isColor ? "\u{1B}[31m\(s)\u{1B}[0m" : s }
    static func bold(_ s: String) -> String    { isColor ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
    static func dim(_ s: String) -> String     { isColor ? "\u{1B}[2m\(s)\u{1B}[0m" : s }
    static func cyanBold(_ s: String) -> String { isColor ? "\u{1B}[1;36m\(s)\u{1B}[0m" : s }
    static func redBold(_ s: String) -> String  { isColor ? "\u{1B}[1;31m\(s)\u{1B}[0m" : s }
    static func whiteBold(_ s: String) -> String { isColor ? "\u{1B}[1;37m\(s)\u{1B}[0m" : s }

    static func success(_ msg: String) {
        print("\(green("✓")) \(msg)")
    }

    static func error(_ msg: String) {
        let output = "\(redBold("✗")) \(msg)\n"
        FileHandle.standardError.write(Data(output.utf8))
    }

    static func verbose(_ msg: String, enabled: Bool) {
        guard enabled else { return }
        let output = "\(dim(msg))\n"
        FileHandle.standardError.write(Data(output.utf8))
    }

    static func printGroupHelp(commandName: String, abstract: String, subcommands: [any ParsableCommand.Type]) {
        let usage = bold("USAGE:") + " " + cyanBold("sloppy") + " " + cyan(commandName) + " " + yellow("<subcommand>") + " " + dim("[options]")

        let nameWidth = subcommands.map { $0.configuration.commandName?.count ?? 0 }.max() ?? 8

        var subLines = ""
        for sub in subcommands {
            let name = sub.configuration.commandName ?? ""
            let padded = name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            subLines += "  \(green(padded))  \(dim(sub.configuration.abstract))\n"
        }

        print("""
        \(dim(abstract))

        \(usage)

        \(bold("SUBCOMMANDS:"))
        \(subLines.trimmingCharacters(in: .newlines))

        Run \(cyanBold("sloppy")) \(cyan(commandName)) \(green("<subcommand>")) \(yellow("--help")) for more information.
        """)
    }

    static func printHelp() {
        let version = SloppyVersion.current
        let v = cyanBold("sloppy") + " " + dim("v\(version)")

        let usage = bold("USAGE:") + " " + cyanBold("sloppy") + " " + yellow("<command>") + " " + dim("[options]")

        let cmds: [(String, String)] = [
            ("run",         "Start the Sloppy server"),
            ("status",      "Check server health"),
            ("update",      "Check for updates"),
            ("agent",       "Manage agents, sessions, memories, cron, skills"),
            ("project",     "Manage projects, tasks, channels"),
            ("channel",     "Inspect and control channels"),
            ("config",      "View and update runtime configuration"),
            ("providers",   "Manage model providers and API keys"),
            ("actor",       "Manage actor board, nodes, links, teams"),
            ("plugin",      "Manage channel plugins"),
            ("mcp",         "Manage MCP servers and tools"),
            ("visor",       "Interact with Visor"),
            ("logs",        "View system logs"),
            ("workers",     "List active workers"),
            ("bulletins",   "View system bulletins"),
            ("token-usage", "View token usage statistics"),
        ]

        let opts: [(String, String)] = [
            ("--url <url>",    "Sloppy server URL (default: from config)"),
            ("--token <token>","Auth token (default: from config)"),
            ("--format <fmt>", "Output format: json, table (default: json)"),
            ("--verbose",      "Show detailed output and HTTP info"),
            ("--version",      "Print version"),
            ("--help",         "Show help for any command"),
        ]

        let cmdWidth = 16
        let optWidth = 20

        var cmdLines = ""
        for (name, desc) in cmds {
            let padded = name.padding(toLength: cmdWidth, withPad: " ", startingAt: 0)
            cmdLines += "  \(green(padded)) \(dim(desc))\n"
        }

        var optLines = ""
        for (flag, desc) in opts {
            let padded = flag.padding(toLength: optWidth, withPad: " ", startingAt: 0)
            optLines += "  \(yellow(padded)) \(dim(desc))\n"
        }

        print("""
        \(v)

        \(usage)

        \(bold("COMMANDS:"))
        \(cmdLines.trimmingCharacters(in: .newlines))

        \(bold("GLOBAL OPTIONS:"))
        \(optLines.trimmingCharacters(in: .newlines))

        Run \(cyanBold("sloppy")) \(green("<command>")) \(yellow("--help")) for more information on a command.
        """)
    }
}
