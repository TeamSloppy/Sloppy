import Foundation

/// Model credentials may come from the Sloppy data directory or the service's environment.
enum ProviderEnvironment {
    static func lookup(
        workspaceRoot: URL,
        processLookup: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> @Sendable (String) -> String? {
        let url = workspaceRoot.appendingPathComponent(".env")
        let values = (try? String(contentsOf: url, encoding: .utf8)).map(parse) ?? [:]
        return { name in processLookup(name) ?? values[name] }
    }

    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var entry = line.trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix("export ") {
                entry = String(entry.dropFirst(7))
            }
            guard !entry.hasPrefix("#"), let equals = entry.firstIndex(of: "=") else { continue }
            let name = entry[..<equals].trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            let raw = entry[entry.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let quote = raw.first, quote == "\"" || quote == "'" {
                let rest = raw.dropFirst()
                guard let end = rest.lastIndex(of: quote) else { continue }
                let suffix = rest[rest.index(after: end)...].trimmingCharacters(in: .whitespaces)
                guard suffix.isEmpty || suffix.hasPrefix("#") else { continue }
                values[name] = String(rest[..<end])
            } else {
                let comment = raw.indices.first { index in
                    raw[index] == "#" && (index == raw.startIndex || raw[raw.index(before: index)].isWhitespace)
                }
                values[name] = raw[..<(comment ?? raw.endIndex)].trimmingCharacters(in: .whitespaces)
            }
        }
        return values
    }
}
