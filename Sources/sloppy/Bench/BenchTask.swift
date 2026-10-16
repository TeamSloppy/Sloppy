import Foundation

/// Declarative description of one benchmark task, stored as `task.json` next to `repo/`, `prompt.md` and `check.sh`.
struct BenchTaskSpec: Codable, Sendable, Equatable {
    var title: String
    var tags: [String]
    var timeoutSeconds: Int
    var checkTimeoutSeconds: Int
    var maxToolCalls: Int?

    init(
        title: String,
        tags: [String] = [],
        timeoutSeconds: Int = 300,
        checkTimeoutSeconds: Int = 120,
        maxToolCalls: Int? = nil
    ) {
        self.title = title
        self.tags = tags
        self.timeoutSeconds = timeoutSeconds
        self.checkTimeoutSeconds = checkTimeoutSeconds
        self.maxToolCalls = maxToolCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 300
        checkTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .checkTimeoutSeconds) ?? 120
        maxToolCalls = try container.decodeIfPresent(Int.self, forKey: .maxToolCalls)
    }
}

struct BenchTask: Sendable, Equatable {
    var id: String
    var spec: BenchTaskSpec
    var prompt: String
    var directory: URL

    var repoDirectory: URL { directory.appendingPathComponent("repo", isDirectory: true) }
    var checkScript: URL { directory.appendingPathComponent("check.sh") }
}

enum BenchTaskError: Error, LocalizedError, Equatable {
    case suiteNotFound(String)
    case invalidTask(String, String)

    var errorDescription: String? {
        switch self {
        case .suiteNotFound(let path):
            return "Benchmark suite not found: \(path)"
        case .invalidTask(let id, let reason):
            return "Invalid benchmark task '\(id)': \(reason)"
        }
    }
}

enum BenchTaskLoader {
    /// Loads every task directory under `suiteDirectory`, sorted by id. `filter` limits tasks by id or tag.
    static func loadSuite(at suiteDirectory: URL, filter: Set<String> = []) throws -> [BenchTask] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: suiteDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BenchTaskError.suiteNotFound(suiteDirectory.path)
        }
        let entries = try fileManager.contentsOfDirectory(
            at: suiteDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var tasks: [BenchTask] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let task = try loadTask(at: entry)
            if filter.isEmpty || filter.contains(task.id) || !filter.isDisjoint(with: task.spec.tags) {
                tasks.append(task)
            }
        }
        return tasks
    }

    static func loadTask(at directory: URL) throws -> BenchTask {
        let id = directory.lastPathComponent
        let fileManager = FileManager.default
        let specURL = directory.appendingPathComponent("task.json")
        let promptURL = directory.appendingPathComponent("prompt.md")
        for required in [specURL, promptURL, directory.appendingPathComponent("check.sh")] {
            guard fileManager.fileExists(atPath: required.path) else {
                throw BenchTaskError.invalidTask(id, "missing \(required.lastPathComponent)")
            }
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.appendingPathComponent("repo").path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw BenchTaskError.invalidTask(id, "missing repo/ directory")
        }
        let spec: BenchTaskSpec
        do {
            spec = try JSONDecoder().decode(BenchTaskSpec.self, from: Data(contentsOf: specURL))
        } catch {
            throw BenchTaskError.invalidTask(id, "task.json: \(error.localizedDescription)")
        }
        let prompt = try String(contentsOf: promptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw BenchTaskError.invalidTask(id, "prompt.md is empty") }
        return BenchTask(id: id, spec: spec, prompt: prompt, directory: directory)
    }
}
