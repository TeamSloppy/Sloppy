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

    static func colorizedHelp(_ message: String) -> String {
        guard isColor && (message.contains("USAGE:") || message.contains("OVERVIEW:")) else {
            return message
        }

        var currentSection: HelpSection?
        return message.split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine -> String in
                let line = String(rawLine)
                if line.hasPrefix("OVERVIEW:") {
                    currentSection = .overview
                    return colorizedInlineHeader("OVERVIEW:", in: line, restStyle: { dim($0) })
                }
                if line.hasPrefix("USAGE:") {
                    currentSection = .usage
                    return colorizedInlineHeader("USAGE:", in: line, restStyle: { colorizedUsageLine($0) })
                }
                if let section = HelpSection(headerLine: line) {
                    currentSection = section
                    return bold(line)
                }

                switch currentSection {
                case .usage:
                    return colorizedUsageLine(line)
                case .options:
                    return colorizedOptionEntry(line)
                case .subcommands:
                    return colorizedCommandEntry(line)
                case .arguments:
                    return colorizedHelpEntry(line, labelStyle: { cyan($0) }, descriptionStyle: { dim($0) })
                case .overview, .none:
                    return line
                }
            }
            .joined(separator: "\n")
    }

    private static func colorizedInlineHeader(
        _ header: String,
        in line: String,
        restStyle: (String) -> String
    ) -> String {
        let rest = String(line.dropFirst(header.count))
        return bold(header) + restStyle(rest)
    }

    private enum HelpSection {
        case overview
        case usage
        case options
        case subcommands
        case arguments

        init?(headerLine: String) {
            switch headerLine {
            case "OVERVIEW:":
                self = .overview
            case "USAGE:":
                self = .usage
            case "OPTIONS:":
                self = .options
            case "SUBCOMMANDS:":
                self = .subcommands
            case "ARGUMENTS:":
                self = .arguments
            default:
                return nil
            }
        }
    }

    private static func colorizedUsageLine(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: false)
            .map { rawToken -> String in
                let token = String(rawToken)
                if token == "sloppy" {
                    return cyanBold(token)
                }
                if token.hasPrefix("--") || token.hasPrefix("[--") {
                    return yellow(token)
                }
                if token.hasPrefix("<") || token.hasPrefix("[<") {
                    return green(token)
                }
                if token.hasPrefix("[") {
                    return dim(token)
                }
                return token
            }
            .joined(separator: " ")
    }

    private static func colorizedOptionEntry(_ line: String) -> String {
        guard let labelRange = line.rangeOfFirstHelpLabel else {
            return line
        }

        let prefix = String(line[..<labelRange.lowerBound])
        let rest = String(line[labelRange.lowerBound...])
        guard rest.hasPrefix("-") else {
            return prefix + dim(rest)
        }

        let split = rest.optionLabelSplit
        guard !split.description.isEmpty else {
            return prefix + yellow(rest)
        }
        return prefix + yellow(split.label) + split.separator + dim(split.description)
    }

    private static func colorizedCommandEntry(_ line: String) -> String {
        guard let labelRange = line.rangeOfFirstHelpLabel else {
            return line
        }

        let prefix = String(line[..<labelRange.lowerBound])
        let rest = String(line[labelRange.lowerBound...])
        if prefix.count > 2 {
            return prefix + dim(rest)
        }
        if rest.hasPrefix("See ") {
            return prefix + dim(rest)
        }
        return colorizedHelpEntry(line, labelStyle: { green($0) }, descriptionStyle: { dim($0) })
    }

    private static func colorizedHelpEntry(
        _ line: String,
        labelStyle: (String) -> String,
        descriptionStyle: (String) -> String
    ) -> String {
        guard let labelRange = line.rangeOfFirstHelpLabel else {
            return line
        }

        let prefix = String(line[..<labelRange.lowerBound])
        let rest = String(line[labelRange.lowerBound...])
        guard let separatorRange = rest.rangeOfHelpColumnSeparator else {
            return prefix + labelStyle(rest)
        }

        let label = String(rest[..<separatorRange.lowerBound])
        let separator = String(rest[separatorRange])
        let description = String(rest[separatorRange.upperBound...])
        return prefix + labelStyle(label) + separator + descriptionStyle(description)
    }

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
            ("service",     "Manage the background service (install/uninstall/start/stop)"),
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

private extension String {
    var rangeOfFirstHelpLabel: Range<String.Index>? {
        guard let firstNonSpace = firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        return firstNonSpace..<endIndex
    }

    var rangeOfHelpColumnSeparator: Range<String.Index>? {
        var cursor = startIndex
        var runStart: String.Index?
        var runLength = 0

        while cursor < endIndex {
            if self[cursor] == " " {
                if runStart == nil {
                    runStart = cursor
                }
                runLength += 1
            } else {
                if runLength >= 2, let runStart {
                    return runStart..<cursor
                }
                runStart = nil
                runLength = 0
            }
            cursor = index(after: cursor)
        }

        if runLength >= 2, let runStart {
            return runStart..<endIndex
        }
        return nil
    }

    var optionLabelSplit: (label: String, separator: String, description: String) {
        var cursor = startIndex
        var labelEnd = startIndex
        var separatorEnd = startIndex
        var foundLabelToken = false

        while cursor < endIndex {
            let tokenStart = cursor
            var tokenEnd = tokenStart
            while tokenEnd < endIndex, self[tokenEnd] != " " {
                tokenEnd = index(after: tokenEnd)
            }

            let token = String(self[tokenStart..<tokenEnd])
            guard token.isHelpOptionLabelToken else {
                break
            }

            foundLabelToken = true
            labelEnd = tokenEnd
            cursor = tokenEnd
            while cursor < endIndex, self[cursor] == " " {
                cursor = index(after: cursor)
            }
            separatorEnd = cursor
        }

        guard foundLabelToken else {
            return ("", "", self)
        }

        return (
            String(self[..<labelEnd]),
            String(self[labelEnd..<separatorEnd]),
            String(self[separatorEnd...])
        )
    }
}

private extension String {
    var isHelpOptionLabelToken: Bool {
        if hasPrefix("-") {
            return true
        }
        return hasPrefix("<") && hasSuffix(">")
    }
}
