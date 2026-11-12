import Foundation

/// Resolves only whole-value ENV references. Never expands shell expressions or mutates configuration.
enum ProviderAPIKeyResolver {
    struct Resolution {
        let key: String
        let usedEnvironmentKey: Bool
    }

    enum ResolutionError: LocalizedError {
        case invalidReference
        case missingEnvironmentVariable(String)

        var errorDescription: String? {
            switch self {
            case .invalidReference:
                return "Invalid API key environment reference. Use $NAME or ${NAME}."
            case .missingEnvironmentVariable(let name):
                return "API key environment variable \(name) is missing or empty in the Sloppy Core environment."
            }
        }
    }

    static func resolve(
        configured: String?,
        fallbackEnvironmentVariable: String = "OPENAI_API_KEY",
        environmentLookup: (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) throws -> Resolution {
        let value = (configured ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            let key = (environmentLookup(fallbackEnvironmentVariable) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Resolution(key: key, usedEnvironmentKey: !key.isEmpty)
        }
        guard value.hasPrefix("$") else {
            return Resolution(key: value, usedEnvironmentKey: false)
        }
        let name: String
        if value.hasPrefix("${"), value.hasSuffix("}") {
            name = String(value.dropFirst(2).dropLast())
        } else {
            name = String(value.dropFirst())
        }
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
        let allowed = letters.union(CharacterSet(charactersIn: "0123456789"))
        guard let first = name.unicodeScalars.first, letters.contains(first),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ResolutionError.invalidReference
        }
        let key = (environmentLookup(name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ResolutionError.missingEnvironmentVariable(name) }
        return Resolution(key: key, usedEnvironmentKey: true)
    }
}
