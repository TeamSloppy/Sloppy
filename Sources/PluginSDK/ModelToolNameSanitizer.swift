import AnyLanguageModel
import Foundation

/// Converts internal tool identifiers into provider-safe names.
///
/// Sloppy tools use dotted IDs such as `files.read`; OpenAI-compatible native
/// tool calling only accepts names matching `^[a-zA-Z0-9_-]{1,128}$`.
public enum ModelToolNameSanitizer {
    public static let maximumNameLength = 128

    public struct Result: Sendable {
        public var tools: [any Tool]
        public var nameMap: [String: String]

        public init(tools: [any Tool], nameMap: [String: String]) {
            self.tools = tools
            self.nameMap = nameMap
        }
    }

    public static func sanitizeTools(_ tools: [any Tool]) -> Result {
        var usedNames = Set<String>()
        var sanitizedTools: [any Tool] = []
        var nameMap: [String: String] = [:]

        sanitizedTools.reserveCapacity(tools.count)
        for tool in tools {
            let sanitizedName = uniqueSanitizedName(for: tool.name, usedNames: &usedNames)
            sanitizedTools.append(SanitizedLanguageModelTool(wrapping: tool, name: sanitizedName))
            nameMap[sanitizedName] = tool.name
        }

        return Result(tools: sanitizedTools, nameMap: nameMap)
    }

    public static func sanitizeName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> Character in
            if isAllowedNameScalar(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        let joined = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let fallback = joined.isEmpty ? "tool" : joined
        return String(fallback.prefix(maximumNameLength))
    }

    private static func uniqueSanitizedName(for name: String, usedNames: inout Set<String>) -> String {
        let base = sanitizeName(name)
        if usedNames.insert(base).inserted {
            return base
        }

        let suffix = "_\(stableHash(name))"
        let prefixLength = max(1, maximumNameLength - suffix.count)
        var candidate = String(base.prefix(prefixLength)) + suffix
        var counter = 2
        while !usedNames.insert(candidate).inserted {
            let retrySuffix = "\(suffix)_\(counter)"
            let retryPrefixLength = max(1, maximumNameLength - retrySuffix.count)
            candidate = String(base.prefix(retryPrefixLength)) + retrySuffix
            counter += 1
        }
        return candidate
    }

    private static func isAllowedNameScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 45, 95:
            return true
        default:
            return false
        }
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 36)
    }
}

public struct SanitizedLanguageModelTool: Tool {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    private let wrapped: any Tool
    public let originalName: String
    public let name: String

    public init(wrapping wrapped: any Tool, name: String) {
        self.wrapped = wrapped
        self.originalName = wrapped.name
        self.name = name
    }

    public var description: String {
        wrapped.description
    }

    public var parameters: GenerationSchema {
        wrapped.parameters
    }

    public var includesSchemaInInstructions: Bool {
        wrapped.includesSchemaInInstructions
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        ""
    }
}
