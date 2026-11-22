import Foundation
import Protocols

/// Records committed mutations synchronously inside the per-file transaction.
/// The lock orders those records with the snapshot at turn completion without
/// suspending a transaction between its write and its record.
final class AgentTurnFileChanges: @unchecked Sendable {
    @TaskLocal static var current: AgentTurnFileChanges?

    private static let maxFiles = 32
    private static let maxFileBytes = 128 * 1_024
    private static let maxOutputBytes = 72 * 1_024

    private struct State {
        let firstHash: String?
        var lastHash: String
        var before: Data?
        var after: Data?
        var interleaved: Bool
        var limited: Bool
    }

    private let lock = NSLock()
    private var files: [String: State] = [:]
    private var omittedFiles = false
    private var finished = false

    func record(path: String, before: Data?, beforeHash: String?, after: Data, afterHash: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        if var file = files[path] {
            file.interleaved = file.interleaved || file.lastHash != beforeHash
            file.limited = file.limited || after.count > Self.maxFileBytes
            file.lastHash = afterHash
            if file.interleaved || file.limited {
                file.before = nil
                file.after = nil
            } else {
                file.after = after
            }
            files[path] = file
            return
        }
        guard beforeHash != afterHash else { return }
        guard files.count < Self.maxFiles else { omittedFiles = true; return }
        let limited = max(before?.count ?? 0, after.count) > Self.maxFileBytes
        files[path] = State(firstHash: beforeHash, lastHash: afterHash,
            before: limited ? nil : before, after: limited ? nil : after, interleaved: false, limited: limited)
    }

    func finish() -> AgentTurnDiff? {
        lock.lock()
        finished = true
        let snapshot = files
        files.removeAll()
        var truncated = omittedFiles
        lock.unlock()

        var remaining = Self.maxOutputBytes
        var result: [AgentTurnDiff.File] = []
        for path in snapshot.keys.sorted() {
            guard let file = snapshot[path] else { continue }
            if file.interleaved {
                result.append(.init(path: path, attribution: .interleaved))
                continue
            }
            guard file.firstHash != file.lastHash else { continue }
            if let after = file.after,
               let patch = AgentTurnUnifiedPatch.make(path: path, before: file.before, after: after),
               patch.text.utf8.count <= remaining {
                remaining -= patch.text.utf8.count
                result.append(.init(path: path, attribution: .verified, patch: patch.text,
                    additions: patch.additions, deletions: patch.deletions))
            } else {
                truncated = true
                result.append(.init(path: path, attribution: .limited))
            }
        }
        return result.isEmpty && !truncated ? nil : AgentTurnDiff(files: result, truncated: truncated)
    }
}

private struct AgentTurnUnifiedPatch {
    let text: String
    let additions: Int
    let deletions: Int

    private struct Line: Equatable {
        let data: Data
        let terminated: Bool
    }

    private struct Row {
        let prefix: Character
        let line: Line
        let oldIndex: Int
        let newIndex: Int
    }

    static func make(path: String, before: Data?, after: Data) -> Self? {
        guard before?.contains(0) != true, !after.contains(0) else { return nil }
        let old = lines(in: before ?? Data())
        let new = lines(in: after)
        // Limit worst-case work for unrelated collections.
        guard (old.count + 1) * (new.count + 1) <= 2_000_000 else { return nil }
        let difference = new.difference(from: old)
        let removed = Set(difference.removals.compactMap { change in
            if case .remove(let index, _, _) = change { index } else { nil }
        })
        let inserted = Set(difference.insertions.compactMap { change in
            if case .insert(let index, _, _) = change { index } else { nil }
        })
        var rows: [Row] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if removed.contains(oldIndex) {
                rows.append(.init(prefix: "-", line: old[oldIndex], oldIndex: oldIndex, newIndex: newIndex))
                oldIndex += 1
            } else if inserted.contains(newIndex) {
                rows.append(.init(prefix: "+", line: new[newIndex], oldIndex: oldIndex, newIndex: newIndex))
                newIndex += 1
            } else {
                rows.append(.init(prefix: " ", line: old[oldIndex], oldIndex: oldIndex, newIndex: newIndex))
                oldIndex += 1
                newIndex += 1
            }
        }
        let label = path.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        let source = before == nil ? "/dev/null" : label
        var text = "--- \(source)\n+++ \(label)\n"
        var hunks: [Range<Int>] = []
        for index in rows.indices where rows[index].prefix != " " {
            let range = max(0, index - 3)..<min(rows.count, index + 4)
            if let last = hunks.last, last.upperBound >= range.lowerBound {
                hunks[hunks.count - 1] = last.lowerBound..<range.upperBound
            } else {
                hunks.append(range)
            }
        }
        for range in hunks {
            let hunk = rows[range]
            let oldCount = hunk.filter { $0.prefix != "+" }.count
            let newCount = hunk.filter { $0.prefix != "-" }.count
            let first = rows[range.lowerBound]
            let oldStart = first.oldIndex + (oldCount == 0 ? 0 : 1)
            let newStart = first.newIndex + (newCount == 0 ? 0 : 1)
            text += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
            for row in hunk {
                text += "\(row.prefix)\(String(decoding: row.line.data, as: UTF8.self))\n"
                if !row.line.terminated { text += "\\ No newline at end of file\n" }
            }
        }
        return Self(text: text, additions: inserted.count, deletions: removed.count)
    }

    private static func lines(in data: Data) -> [Line] {
        guard !data.isEmpty else { return [] }
        let terminated = data.last == 10
        var pieces = data.split(separator: 10, omittingEmptySubsequences: false)
        if terminated { pieces.removeLast() }
        return pieces.enumerated().map { index, piece in
            Line(data: Data(piece), terminated: terminated || index < pieces.count - 1)
        }
    }
}
