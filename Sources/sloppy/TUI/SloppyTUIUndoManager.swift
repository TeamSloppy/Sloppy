import Foundation

struct SloppyTUIUndoManager {
    enum ApplyDirection: Equatable {
        case undo
        case redo
    }

    struct Baseline {
        var rootURL: URL
        fileprivate var fingerprints: [String: FileFingerprint]
        fileprivate var contents: [String: Data]
    }

    struct ApplyResult: Equatable {
        var direction: ApplyDirection
        var paths: [String]
    }

    struct DiffResult: Equatable {
        var diff: String
        var linesAdded: Int
        var linesDeleted: Int
        var paths: [String]
        var truncated: Bool

        var hasChanges: Bool {
            !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    enum RecordResult: Equatable {
        case recorded(paths: [String])
        case noChanges
        case skipped(String)
    }

    enum Error: LocalizedError, Equatable {
        case nothingToUndo
        case nothingToRedo
        case conflict(path: String)
        case oversized(path: String, bytes: Int)
        case filesystem(String)

        var errorDescription: String? {
            switch self {
            case .nothingToUndo:
                return "Nothing to undo."
            case .nothingToRedo:
                return "Nothing to redo."
            case .conflict(let path):
                return "Cannot apply because `\(path)` changed since the undo point was recorded."
            case .oversized(let path, let bytes):
                return "`\(path)` is too large for TUI undo history (\(bytes) bytes)."
            case .filesystem(let message):
                return message
            }
        }
    }

    static let maxHistoryDepth = 20
    static let maxFileBytes = 5 * 1024 * 1024
    static let maxTurnBytes = 25 * 1024 * 1024
    static let maxBaselineBytes = 25 * 1024 * 1024

    private var undoStack: [Transaction] = []
    private var redoStack: [Transaction] = []
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func sessionDiff(rootURL: URL, maxCharacters: Int = 96 * 1024) throws -> DiffResult {
        let root = rootURL.standardizedFileURL
        var initialStates: [String: FileState] = [:]
        for transaction in undoStack {
            for path in transaction.paths where initialStates[path] == nil {
                initialStates[path] = transaction.before[path] ?? .missing
            }
        }

        var chunks: [String] = []
        var changedPaths: [String] = []
        var linesAdded = 0
        var linesDeleted = 0
        var characterCount = 0
        var truncated = false

        for path in initialStates.keys.sorted() {
            guard let before = initialStates[path] else {
                continue
            }
            let after = try readState(rootURL: root, path: path)
            guard before != after else {
                continue
            }

            let fileDiff = Self.unifiedDiff(path: path, before: before, after: after)
            guard !fileDiff.text.isEmpty else {
                continue
            }

            changedPaths.append(path)
            linesAdded += fileDiff.linesAdded
            linesDeleted += fileDiff.linesDeleted

            let separatorCount = chunks.isEmpty ? 0 : 1
            let nextCount = characterCount + separatorCount + fileDiff.text.count
            if nextCount > maxCharacters {
                let remaining = max(0, maxCharacters - characterCount - separatorCount)
                if remaining > 0 {
                    if !chunks.isEmpty {
                        chunks.append("")
                    }
                    chunks.append(String(fileDiff.text.prefix(remaining)))
                }
                truncated = true
                break
            }

            chunks.append(fileDiff.text)
            characterCount = nextCount
        }

        return DiffResult(
            diff: chunks.joined(separator: "\n"),
            linesAdded: linesAdded,
            linesDeleted: linesDeleted,
            paths: changedPaths,
            truncated: truncated
        )
    }

    func makeBaseline(rootURL: URL) -> Baseline {
        let root = rootURL.standardizedFileURL
        let fingerprints = scanFingerprints(rootURL: root)
        var contents: [String: Data] = [:]
        var capturedBytes = 0

        for path in fingerprints.keys.sorted() {
            let fileURL = root.appendingPathComponent(path)
            guard let size = fingerprints[path]?.sizeBytes,
                  size <= Self.maxFileBytes,
                  capturedBytes + size <= Self.maxBaselineBytes,
                  let data = try? Data(contentsOf: fileURL)
            else {
                continue
            }
            contents[path] = data
            capturedBytes += data.count
        }

        return Baseline(rootURL: root, fingerprints: fingerprints, contents: contents)
    }

    mutating func recordChanges(rootURL: URL, baseline: Baseline) -> RecordResult {
        let root = rootURL.standardizedFileURL
        let current = scanFingerprints(rootURL: root)
        var candidatePathSet = Set(baseline.fingerprints.keys)
            .union(current.keys)
            .filter { baseline.fingerprints[$0] != current[$0] }

        for (path, beforeData) in baseline.contents where current[path] != nil && !candidatePathSet.contains(path) {
            let fileURL = root.appendingPathComponent(path)
            if let currentData = try? Data(contentsOf: fileURL), currentData != beforeData {
                candidatePathSet.insert(path)
            }
        }

        let candidatePaths = candidatePathSet.sorted()

        guard !candidatePaths.isEmpty else {
            return .noChanges
        }

        var before: [String: FileState] = [:]
        var after: [String: FileState] = [:]
        var recordedPaths: [String] = []
        var totalBytes = 0

        for path in candidatePaths {
            let beforeState: FileState
            if baseline.fingerprints[path] == nil {
                beforeState = .missing
            } else if let data = baseline.contents[path] {
                beforeState = .file(data)
            } else {
                return .skipped("Undo history skipped because `\(path)` was not captured before the turn. Files above 5 MiB and snapshots beyond 25 MiB are not recorded.")
            }

            let afterState: FileState
            do {
                afterState = try readState(rootURL: root, path: path)
            } catch let error as Error {
                return .skipped(error.localizedDescription)
            } catch {
                return .skipped(String(describing: error))
            }

            guard beforeState != afterState else {
                continue
            }

            totalBytes += beforeState.byteCount + afterState.byteCount
            guard totalBytes <= Self.maxTurnBytes else {
                return .skipped("Undo history skipped because this turn changed more than 25 MiB.")
            }

            before[path] = beforeState
            after[path] = afterState
            recordedPaths.append(path)
        }

        guard !recordedPaths.isEmpty else {
            return .noChanges
        }

        undoStack.append(Transaction(paths: recordedPaths, before: before, after: after))
        if undoStack.count > Self.maxHistoryDepth {
            undoStack.removeFirst(undoStack.count - Self.maxHistoryDepth)
        }
        redoStack.removeAll(keepingCapacity: true)
        return .recorded(paths: recordedPaths)
    }

    mutating func undo(rootURL: URL) throws -> ApplyResult {
        guard let transaction = undoStack.last else {
            throw Error.nothingToUndo
        }
        let root = rootURL.standardizedFileURL
        try validate(transaction.after, rootURL: root)
        try apply(transaction.before, rootURL: root)
        undoStack.removeLast()
        redoStack.append(transaction)
        return ApplyResult(direction: .undo, paths: transaction.paths)
    }

    mutating func redo(rootURL: URL) throws -> ApplyResult {
        guard let transaction = redoStack.last else {
            throw Error.nothingToRedo
        }
        let root = rootURL.standardizedFileURL
        try validate(transaction.before, rootURL: root)
        try apply(transaction.after, rootURL: root)
        redoStack.removeLast()
        undoStack.append(transaction)
        return ApplyResult(direction: .redo, paths: transaction.paths)
    }

    private func scanFingerprints(rootURL: URL) -> [String: FileFingerprint] {
        var result: [String: FileFingerprint] = [:]
        walk(directoryURL: rootURL, relativeDirectory: "", result: &result)
        return result
    }

    private func walk(directoryURL: URL, relativeDirectory: String, result: inout [String: FileFingerprint]) {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        )) ?? []

        for url in urls {
            let name = url.lastPathComponent
            let relativePath = relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                guard !Self.excludedDirectoryNames.contains(name) else {
                    continue
                }
                walk(directoryURL: url, relativeDirectory: relativePath, result: &result)
            } else {
                result[relativePath] = FileFingerprint(
                    sizeBytes: values?.fileSize ?? 0,
                    modifiedAt: values?.contentModificationDate
                )
            }
        }
    }

    private func readState(rootURL: URL, path: String) throws -> FileState {
        let fileURL = rootURL.appendingPathComponent(path)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory != true else {
            throw Error.conflict(path: path)
        }
        let size = values.fileSize ?? 0
        guard size <= Self.maxFileBytes else {
            throw Error.oversized(path: path, bytes: size)
        }
        return .file(try Data(contentsOf: fileURL))
    }

    private func validate(_ expected: [String: FileState], rootURL: URL) throws {
        for path in expected.keys.sorted() {
            guard let expectedState = expected[path],
                  try readState(rootURL: rootURL, path: path) == expectedState
            else {
                throw Error.conflict(path: path)
            }
        }
    }

    private func apply(_ states: [String: FileState], rootURL: URL) throws {
        for path in states.keys.sorted() {
            guard let state = states[path] else {
                continue
            }
            let fileURL = rootURL.appendingPathComponent(path)
            do {
                switch state {
                case .missing:
                    if fileManager.fileExists(atPath: fileURL.path) {
                        try fileManager.removeItem(at: fileURL)
                    }
                case .file(let data):
                    try fileManager.createDirectory(
                        at: fileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                throw Error.filesystem(error.localizedDescription)
            }
        }
    }

    private static let excludedDirectoryNames: Set<String> = [
        ".git",
        ".sloppy",
        ".sloppy-worktrees",
        ".build",
        "node_modules",
        "dist",
        "DerivedData",
    ]

    private static func unifiedDiff(path: String, before: FileState, after: FileState) -> FileDiff {
        let beforeText = before.textLines
        let afterText = after.textLines
        guard let beforeText, let afterText else {
            return FileDiff(
                text: """
                diff --git a/\(path) b/\(path)
                Binary files \(before.isMissing ? "/dev/null" : "a/\(path)") and \(after.isMissing ? "/dev/null" : "b/\(path)") differ
                """,
                linesAdded: 0,
                linesDeleted: 0
            )
        }

        let operations = diffOperations(from: beforeText, to: afterText)
        guard operations.contains(where: \.isChange) else {
            return FileDiff(text: "", linesAdded: 0, linesDeleted: 0)
        }

        let linesAdded = operations.filter(\.isInsertion).count
        let linesDeleted = operations.filter(\.isDeletion).count
        var lines: [String] = ["diff --git a/\(path) b/\(path)"]
        if before.isMissing {
            lines.append("new file mode 100644")
        } else if after.isMissing {
            lines.append("deleted file mode 100644")
        }
        lines.append(before.isMissing ? "--- /dev/null" : "--- a/\(path)")
        lines.append(after.isMissing ? "+++ /dev/null" : "+++ b/\(path)")
        lines.append(contentsOf: unifiedHunkLines(operations))
        return FileDiff(text: lines.joined(separator: "\n"), linesAdded: linesAdded, linesDeleted: linesDeleted)
    }

    private static func diffOperations(from oldLines: [String], to newLines: [String]) -> [LineDiffOperation] {
        let cellCount = (oldLines.count + 1) * (newLines.count + 1)
        guard cellCount <= 2_000_000 else {
            return boundedDiffOperations(from: oldLines, to: newLines)
        }

        let columns = newLines.count + 1
        var table = Array(repeating: 0, count: cellCount)
        if !oldLines.isEmpty && !newLines.isEmpty {
            for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
                for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                    let index = oldIndex * columns + newIndex
                    if oldLines[oldIndex] == newLines[newIndex] {
                        table[index] = table[(oldIndex + 1) * columns + newIndex + 1] + 1
                    } else {
                        table[index] = max(
                            table[(oldIndex + 1) * columns + newIndex],
                            table[oldIndex * columns + newIndex + 1]
                        )
                    }
                }
            }
        }

        var operations: [LineDiffOperation] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == newLines[newIndex] {
                operations.append(.context(oldLines[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if newIndex == newLines.count
                || (oldIndex < oldLines.count
                    && table[(oldIndex + 1) * columns + newIndex] >= table[oldIndex * columns + newIndex + 1]) {
                operations.append(.delete(oldLines[oldIndex]))
                oldIndex += 1
            } else {
                operations.append(.insert(newLines[newIndex]))
                newIndex += 1
            }
        }
        return operations
    }

    private static func boundedDiffOperations(from oldLines: [String], to newLines: [String]) -> [LineDiffOperation] {
        var prefixCount = 0
        while prefixCount < oldLines.count,
              prefixCount < newLines.count,
              oldLines[prefixCount] == newLines[prefixCount] {
            prefixCount += 1
        }

        var oldSuffixIndex = oldLines.count
        var newSuffixIndex = newLines.count
        while oldSuffixIndex > prefixCount,
              newSuffixIndex > prefixCount,
              oldLines[oldSuffixIndex - 1] == newLines[newSuffixIndex - 1] {
            oldSuffixIndex -= 1
            newSuffixIndex -= 1
        }

        return oldLines[..<prefixCount].map(LineDiffOperation.context)
            + oldLines[prefixCount..<oldSuffixIndex].map(LineDiffOperation.delete)
            + newLines[prefixCount..<newSuffixIndex].map(LineDiffOperation.insert)
            + oldLines[oldSuffixIndex...].map(LineDiffOperation.context)
    }

    private static func unifiedHunkLines(_ operations: [LineDiffOperation]) -> [String] {
        guard let firstChange = operations.firstIndex(where: \.isChange),
              let lastChange = operations.lastIndex(where: \.isChange)
        else {
            return []
        }

        let contextLineCount = 3
        let start = max(0, firstChange - contextLineCount)
        let end = min(operations.count, lastChange + contextLineCount + 1)
        var oldLine = 1
        var newLine = 1
        for operation in operations[..<start] {
            if operation.consumesOldLine {
                oldLine += 1
            }
            if operation.consumesNewLine {
                newLine += 1
            }
        }

        let hunk = operations[start..<end]
        let oldCount = hunk.filter(\.consumesOldLine).count
        let newCount = hunk.filter(\.consumesNewLine).count
        let oldStart = oldCount == 0 ? max(0, oldLine - 1) : oldLine
        let newStart = newCount == 0 ? max(0, newLine - 1) : newLine
        var lines = ["@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"]
        lines.append(contentsOf: hunk.map(\.unifiedLine))
        return lines
    }
}

struct SloppyTUISessionUndoManagers {
    struct Baseline {
        var sessionID: String
        var baseline: SloppyTUIUndoManager.Baseline
    }

    private var managers: [String: SloppyTUIUndoManager] = [:]

    func makeBaseline(sessionID: String, rootURL: URL) -> Baseline {
        let manager = managers[sessionID] ?? SloppyTUIUndoManager()
        return Baseline(
            sessionID: sessionID,
            baseline: manager.makeBaseline(rootURL: rootURL)
        )
    }

    mutating func recordChanges(_ baseline: Baseline) -> SloppyTUIUndoManager.RecordResult {
        var manager = managers[baseline.sessionID] ?? SloppyTUIUndoManager()
        let result = manager.recordChanges(rootURL: baseline.baseline.rootURL, baseline: baseline.baseline)
        managers[baseline.sessionID] = manager
        return result
    }

    mutating func undo(sessionID: String, rootURL: URL) throws -> SloppyTUIUndoManager.ApplyResult {
        var manager = managers[sessionID] ?? SloppyTUIUndoManager()
        let result = try manager.undo(rootURL: rootURL)
        managers[sessionID] = manager
        return result
    }

    mutating func redo(sessionID: String, rootURL: URL) throws -> SloppyTUIUndoManager.ApplyResult {
        var manager = managers[sessionID] ?? SloppyTUIUndoManager()
        let result = try manager.redo(rootURL: rootURL)
        managers[sessionID] = manager
        return result
    }

    func canUndo(sessionID: String) -> Bool {
        managers[sessionID]?.canUndo ?? false
    }

    func canRedo(sessionID: String) -> Bool {
        managers[sessionID]?.canRedo ?? false
    }

    func sessionDiff(sessionID: String, rootURL: URL, maxCharacters: Int = 96 * 1024) throws -> SloppyTUIUndoManager.DiffResult {
        guard let manager = managers[sessionID] else {
            return SloppyTUIUndoManager.DiffResult(
                diff: "",
                linesAdded: 0,
                linesDeleted: 0,
                paths: [],
                truncated: false
            )
        }
        return try manager.sessionDiff(rootURL: rootURL, maxCharacters: maxCharacters)
    }
}

private struct Transaction: Equatable {
    var paths: [String]
    var before: [String: FileState]
    var after: [String: FileState]
}

private enum FileState: Equatable {
    case missing
    case file(Data)

    var byteCount: Int {
        switch self {
        case .missing:
            return 0
        case .file(let data):
            return data.count
        }
    }

    var isMissing: Bool {
        if case .missing = self {
            return true
        }
        return false
    }

    var textLines: [String]? {
        switch self {
        case .missing:
            return []
        case .file(let data):
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            if text.isEmpty {
                return []
            }
            var lines = text.components(separatedBy: "\n")
            if text.hasSuffix("\n") {
                lines.removeLast()
            }
            return lines
        }
    }
}

private struct FileFingerprint: Equatable {
    var sizeBytes: Int
    var modifiedAt: Date?
}

private struct FileDiff: Equatable {
    var text: String
    var linesAdded: Int
    var linesDeleted: Int
}

private enum LineDiffOperation: Equatable {
    case context(String)
    case delete(String)
    case insert(String)

    var isChange: Bool {
        switch self {
        case .context:
            return false
        case .delete, .insert:
            return true
        }
    }

    var isDeletion: Bool {
        if case .delete = self {
            return true
        }
        return false
    }

    var isInsertion: Bool {
        if case .insert = self {
            return true
        }
        return false
    }

    var consumesOldLine: Bool {
        switch self {
        case .context, .delete:
            return true
        case .insert:
            return false
        }
    }

    var consumesNewLine: Bool {
        switch self {
        case .context, .insert:
            return true
        case .delete:
            return false
        }
    }

    var unifiedLine: String {
        switch self {
        case .context(let line):
            return " \(line)"
        case .delete(let line):
            return "-\(line)"
        case .insert(let line):
            return "+\(line)"
        }
    }
}
