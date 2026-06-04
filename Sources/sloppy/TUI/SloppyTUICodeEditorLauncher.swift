import Foundation

struct SloppyTUICodeEditorLaunchResult: Sendable, Equatable {
    var label: String
    var path: String
}

enum SloppyTUIEditorCommand {
    static func preferredEditor(args: [String], defaultEditor: String) -> [String] {
        if !args.isEmpty {
            return args
        }
        return SloppyTUICodeEditorLauncher.splitCommandLine(defaultEditor) ?? []
    }
}

enum SloppyTUICodeEditorLauncher {
    enum Error: LocalizedError, Equatable {
        case pathMissing(String)
        case noEditorFound([String])

        var errorDescription: String? {
            switch self {
            case .pathMissing(let path):
                return "Path does not exist: \(path)"
            case .noEditorFound(let attempted):
                let names = attempted.isEmpty ? "none" : attempted.joined(separator: ", ")
                return "No code editor command was found. Tried: \(names). Set SLOPPY_CODE_EDITOR=\"code --reuse-window\" to choose one explicitly."
            }
        }
    }

    struct Command: Sendable, Equatable {
        var executable: String
        var arguments: [String]
        var label: String
        var shouldWaitForExit: Bool
    }

    private static let explicitEnvironmentKeys = [
        "SLOPPY_CODE_EDITOR",
        "SLOPPY_EDITOR",
    ]
    private static let inheritedEnvironmentKeys = [
        "VISUAL",
        "EDITOR",
    ]
    private static let defaultExecutableNames = [
        "code",
        "cursor",
        "windsurf",
        "zed",
        "subl",
        "mate",
        "bbedit",
        "idea",
        "xed",
    ]
    private static let macOSApplicationNames = [
        "Visual Studio Code",
        "Cursor",
        "Windsurf",
        "Zed",
        "Sublime Text",
        "TextMate",
        "BBEdit",
        "IntelliJ IDEA",
        "Xcode",
    ]

    static func open(
        path: String,
        preferredEditor: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) async throws -> SloppyTUICodeEditorLaunchResult {
        try openSynchronously(
            path: path,
            preferredEditor: preferredEditor,
            environment: environment,
            fileManager: fileManager
        )
    }

    static func configuredCommandLine(environment: [String: String]) -> [String]? {
        for key in explicitEnvironmentKeys {
            if let command = splitCommandLine(environment[key] ?? ""), !command.isEmpty {
                return command
            }
        }
        for key in inheritedEnvironmentKeys {
            guard let command = splitCommandLine(environment[key] ?? ""), !command.isEmpty else {
                continue
            }
            let name = URL(fileURLWithPath: command[0]).lastPathComponent
            if defaultExecutableNames.contains(name) {
                return command
            }
        }
        return nil
    }

    static func splitCommandLine(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var words: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in trimmed {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == " " || character == "\t" || character == "\n" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }

        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    static func candidateCommandLabels(
        preferredEditor: [String],
        environment: [String: String]
    ) -> [String] {
        candidateCommands(preferredEditor: preferredEditor, environment: environment).map(\.label)
    }

    private static func openSynchronously(
        path: String,
        preferredEditor: [String],
        environment: [String: String],
        fileManager: FileManager
    ) throws -> SloppyTUICodeEditorLaunchResult {
        let expandedPath = expandTilde(path)
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw Error.pathMissing(expandedPath)
        }

        var attempted: [String] = []
        for command in candidateCommands(preferredEditor: preferredEditor, environment: environment) {
            attempted.append(command.label)
            guard let executableURL = resolveExecutable(
                command.executable,
                environment: environment,
                fileManager: fileManager
            ) else {
                continue
            }
            if launch(
                executableURL: executableURL,
                arguments: command.arguments + [expandedPath],
                currentDirectoryPath: expandedPath,
                shouldWaitForExit: command.shouldWaitForExit
            ) {
                return SloppyTUICodeEditorLaunchResult(label: command.label, path: expandedPath)
            }
        }

        throw Error.noEditorFound(attempted)
    }

    private static func candidateCommands(preferredEditor: [String], environment: [String: String]) -> [Command] {
        if let preferred = preferredCommands(from: preferredEditor), !preferred.isEmpty {
            return preferred
        }

        var commands: [Command] = []
        if let configured = configuredCommandLine(environment: environment), !configured.isEmpty {
            commands.append(Command(
                executable: configured[0],
                arguments: Array(configured.dropFirst()),
                label: configured.joined(separator: " "),
                shouldWaitForExit: false
            ))
        }
        commands += defaultExecutableNames.map { name in
            Command(executable: name, arguments: [], label: name, shouldWaitForExit: false)
        }
        commands += macOSApplicationNames.map { name in
            Command(
                executable: "/usr/bin/open",
                arguments: ["-a", name],
                label: name,
                shouldWaitForExit: true
            )
        }
        return commands
    }

    private static func preferredCommands(from raw: [String]) -> [Command]? {
        let tokens = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = tokens.first else { return nil }

        let rest = Array(tokens.dropFirst())
        let normalized = first.lowercased()
        switch normalized {
        case "code", "vscode", "vs-code", "visual-studio-code":
            return [
                Command(executable: "code", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Visual Studio Code"], label: "Visual Studio Code", shouldWaitForExit: true),
            ]
        case "cursor":
            return [
                Command(executable: "cursor", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Cursor"], label: "Cursor", shouldWaitForExit: true),
            ]
        case "windsurf":
            return [
                Command(executable: "windsurf", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Windsurf"], label: "Windsurf", shouldWaitForExit: true),
            ]
        case "zed":
            return [
                Command(executable: "zed", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Zed"], label: "Zed", shouldWaitForExit: true),
            ]
        case "subl", "sublime", "sublime-text":
            return [
                Command(executable: "subl", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Sublime Text"], label: "Sublime Text", shouldWaitForExit: true),
            ]
        case "mate", "textmate":
            return [
                Command(executable: "mate", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "TextMate"], label: "TextMate", shouldWaitForExit: true),
            ]
        case "bbedit":
            return [
                Command(executable: "bbedit", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "BBEdit"], label: "BBEdit", shouldWaitForExit: true),
            ]
        case "idea", "intellij", "intellij-idea":
            return [
                Command(executable: "idea", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "IntelliJ IDEA"], label: "IntelliJ IDEA", shouldWaitForExit: true),
            ]
        case "xcode", "xed":
            return [
                Command(executable: "xed", arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
                Command(executable: "/usr/bin/open", arguments: ["-a", "Xcode"], label: "Xcode", shouldWaitForExit: true),
            ]
        default:
            return [
                Command(executable: first, arguments: rest, label: ([first] + rest).joined(separator: " "), shouldWaitForExit: false),
            ]
        }
    }

    private static func launch(
        executableURL: URL,
        arguments: [String],
        currentDirectoryPath: String,
        shouldWaitForExit: Bool
    ) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: currentDirectoryPath, isDirectory: &isDirectory), isDirectory.boolValue {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
        }

        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
        } catch {
            return false
        }

        if shouldWaitForExit {
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
        return true
    }

    private static func resolveExecutable(
        _ rawCommand: String,
        environment: [String: String],
        fileManager: FileManager
    ) -> URL? {
        let command = expandTilde(rawCommand)
        if command.contains("/") {
            guard fileManager.isExecutableFile(atPath: command) else { return nil }
            return URL(fileURLWithPath: command)
        }

        let pathValue = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    private static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }
        return home + String(path.dropFirst())
    }
}
