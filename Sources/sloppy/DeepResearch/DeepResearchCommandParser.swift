import Foundation

enum DeepResearchMode: String, CaseIterable, Sendable {
    case compare
    case review
    case explore
}

struct DeepResearchRequest: Equatable, Sendable {
    var mode: DeepResearchMode
    var rounds: Int
    var prompt: String
}

enum DeepResearchCommandParser {
    static let commandName = "deepresearch"
    static let skillID = "sloppy/deep-research"
    static let defaultMode = DeepResearchMode.explore
    static let defaultRounds = 3
    static let minRounds = 1
    static let maxRounds = 8

    enum ValidationError: Error, Equatable, CustomStringConvertible {
        case notDeepResearchCommand
        case missingOptionValue(String)
        case unknownOption(String)
        case invalidMode(String)
        case invalidRounds(Int)
        case invalidRoundsValue(String)
        case missingPrompt
        case unterminatedQuote

        var description: String {
            switch self {
            case .notDeepResearchCommand:
                return "Usage: /deepresearch [--mode compare|review|explore] [--rounds 1...8] <prompt>"
            case .missingOptionValue(let option):
                return "Missing value for \(option)."
            case .unknownOption(let option):
                return "Unknown option \(option)."
            case .invalidMode(let mode):
                return "Invalid deep research mode '\(mode)'. Use compare, review, or explore."
            case .invalidRounds(let rounds):
                return "Invalid deep research rounds \(rounds). Use a value from \(minRounds) to \(maxRounds)."
            case .invalidRoundsValue(let value):
                return "Invalid deep research rounds '\(value)'. Use a number from \(minRounds) to \(maxRounds)."
            case .missingPrompt:
                return "Usage: /deepresearch [--mode compare|review|explore] [--rounds 1...8] <prompt>"
            case .unterminatedQuote:
                return "Unterminated quote in deep research command."
            }
        }
    }

    static func parseSlashCommand(_ text: String) throws -> DeepResearchRequest {
        let tokens = try shellTokens(from: text)
        guard let first = tokens.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.lowercased() == "/\(commandName)"
        else {
            throw ValidationError.notDeepResearchCommand
        }
        return try parseArguments(Array(tokens.dropFirst()))
    }

    static func parseArguments(_ arguments: [String]) throws -> DeepResearchRequest {
        var mode = defaultMode
        var rounds = defaultRounds
        var promptParts: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--mode" {
                index += 1
                guard index < arguments.count else { throw ValidationError.missingOptionValue("--mode") }
                let raw = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let parsed = DeepResearchMode(rawValue: raw) else {
                    throw ValidationError.invalidMode(raw)
                }
                mode = parsed
            } else if argument.hasPrefix("--mode=") {
                let raw = String(argument.dropFirst("--mode=".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let parsed = DeepResearchMode(rawValue: raw) else {
                    throw ValidationError.invalidMode(raw)
                }
                mode = parsed
            } else if argument == "--rounds" {
                index += 1
                guard index < arguments.count else { throw ValidationError.missingOptionValue("--rounds") }
                rounds = try parseRounds(arguments[index])
            } else if argument.hasPrefix("--rounds=") {
                rounds = try parseRounds(String(argument.dropFirst("--rounds=".count)))
            } else if argument.hasPrefix("--") {
                throw ValidationError.unknownOption(argument)
            } else {
                promptParts.append(contentsOf: arguments[index...])
                break
            }
            index += 1
        }

        let prompt = promptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw ValidationError.missingPrompt
        }
        return DeepResearchRequest(mode: mode, rounds: rounds, prompt: prompt)
    }

    static func skillInvocationMessage(for request: DeepResearchRequest) -> String {
        """
        Use installed skill `\(skillID)` for this request.

        Deep research configuration:
        mode: \(request.mode.rawValue)
        rounds: \(request.rounds)

        User request:
        \(request.prompt)
        """
    }

    private static func parseRounds(_ raw: String) throws -> Int {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rounds = Int(value) else {
            throw ValidationError.invalidRoundsValue(value)
        }
        guard rounds >= minRounds && rounds <= maxRounds else {
            throw ValidationError.invalidRounds(rounds)
        }
        return rounds
    }

    private static func shellTokens(from text: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in text {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
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
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }

        if escaping {
            current.append("\\")
        }
        guard quote == nil else {
            throw ValidationError.unterminatedQuote
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
