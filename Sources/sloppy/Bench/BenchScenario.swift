import Foundation

/// A multi-session behavior scenario, stored as `scenario.json`. Text and checks may contain `{{N}}`-style
/// placeholders (`{{A}}`, `{{B}}`, ...) that are replaced by random per-run tokens, so a fact cannot be answered
/// from training data or from an earlier run's leftovers.
struct BenchScenarioSpec: Codable, Sendable, Equatable {
    struct Step: Codable, Sendable, Equatable {
        /// Sessions are created on first use; a new name is a fresh session of the same agent.
        var session: String
        var say: String
        /// Lets checks refer to this step's reply.
        var id: String?
        /// Runs an explicit memory checkpoint on `session` after this step.
        var checkpointAfter: Bool?
        var mode: String?
    }

    enum CheckKind: String, Codable, Sendable {
        case replyHas = "reply_has"
        case replyLacks = "reply_lacks"
    }

    struct Check: Codable, Sendable, Equatable {
        var kind: CheckKind
        /// The `id` of the step whose reply is inspected.
        var step: String
        var token: String
    }

    var title: String
    var tags: [String]
    var timeoutSeconds: Int
    var steps: [Step]
    var checks: [Check]
    /// Tokens whose storage location is reported as a diagnostic (not part of pass/fail).
    var trackedTokens: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 900
        steps = try container.decode([Step].self, forKey: .steps)
        checks = try container.decode([Check].self, forKey: .checks)
        trackedTokens = try container.decodeIfPresent([String].self, forKey: .trackedTokens) ?? []
    }

    init(title: String, tags: [String] = [], timeoutSeconds: Int = 900, steps: [Step], checks: [Check], trackedTokens: [String] = []) {
        self.title = title
        self.tags = tags
        self.timeoutSeconds = timeoutSeconds
        self.steps = steps
        self.checks = checks
        self.trackedTokens = trackedTokens
    }

    /// Replaces every `{{X}}` placeholder with a random token that is stable within this call.
    func instantiated(using generator: () -> String) -> BenchScenarioSpec {
        var tokens: [String: String] = [:]
        func expand(_ text: String) -> String {
            var result = text
            let pattern = try? NSRegularExpression(pattern: "\\{\\{([A-Za-z0-9_]+)\\}\\}")
            let matches = pattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            // Assign tokens in reading order, then substitute from the end so earlier ranges stay valid.
            for match in matches {
                guard let name = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[name])
                if tokens[key] == nil { tokens[key] = generator() }
            }
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result), let name = Range(match.range(at: 1), in: text),
                      let token = tokens[String(text[name])]
                else { continue }
                result.replaceSubrange(whole, with: token)
            }
            return result
        }
        var copy = self
        // Expand in reading order so a placeholder gets the same token everywhere it appears.
        copy.steps = steps.map { var step = $0; step.say = expand(step.say); return step }
        copy.checks = checks.map { var check = $0; check.token = expand(check.token); return check }
        copy.trackedTokens = trackedTokens.map(expand)
        return copy
    }
}

struct BenchScenario: Sendable, Equatable {
    var id: String
    var spec: BenchScenarioSpec
}

enum BenchScenarioLoader {
    static func loadSuite(at directory: URL, filter: Set<String> = []) throws -> [BenchScenario] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BenchTaskError.suiteNotFound(directory.path)
        }
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var scenarios: [BenchScenario] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where entry.pathExtension == "json" {
            let id = entry.deletingPathExtension().lastPathComponent
            let spec: BenchScenarioSpec
            do {
                spec = try JSONDecoder().decode(BenchScenarioSpec.self, from: Data(contentsOf: entry))
            } catch {
                throw BenchTaskError.invalidTask(id, "\(entry.lastPathComponent): \(error.localizedDescription)")
            }
            let stepIDs = Set(spec.steps.compactMap(\.id))
            for check in spec.checks where !stepIDs.contains(check.step) {
                throw BenchTaskError.invalidTask(id, "check refers to unknown step '\(check.step)'")
            }
            if filter.isEmpty || filter.contains(id) || !filter.isDisjoint(with: spec.tags) {
                scenarios.append(BenchScenario(id: id, spec: spec))
            }
        }
        return scenarios
    }
}
