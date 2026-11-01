import Foundation
import Observation

struct BrowserFavoriteEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case page, folder }
    var id = UUID()
    var kind: Kind
    var title: String
    var url: URL?
    var parentID: UUID?
    var isCollapsed = false
}

@Observable @MainActor
final class BrowserFavoritesStore {
    static let shared = BrowserFavoritesStore()
    static let storageKey = "sloppy.browser.favorites.v1"
    private let defaults: UserDefaults
    private(set) var entries: [BrowserFavoriteEntry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([BrowserFavoriteEntry].self, from: $0) } ?? []
        var seen = Set<UUID>()
        entries = saved.compactMap { entry in
            guard seen.insert(entry.id).inserted else { return nil }
            var entry = entry
            if entry.kind == .page {
                guard let url = BrowserSearchEngine.websiteURL(entry.url) else { return nil }
                entry.url = url
            } else { entry.url = nil }
            if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.title = entry.url?.host ?? "Folder"
            }
            return entry
        }
        let folders = Set(entries.filter { $0.kind == .folder }.map(\.id))
        for index in entries.indices {
            if let parent = entries[index].parentID, !folders.contains(parent) || parent == entries[index].id {
                entries[index].parentID = nil
            }
        }
        let parents = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.parentID) })
        for index in entries.indices {
            var visited: Set<UUID> = [entries[index].id]
            var parent = entries[index].parentID
            while let id = parent {
                guard visited.insert(id).inserted else { entries[index].parentID = nil; break }
                parent = parents[id] ?? nil
            }
        }
    }

    func entry(_ id: UUID) -> BrowserFavoriteEntry? { entries.first { $0.id == id } }
    func children(in parentID: UUID?) -> [BrowserFavoriteEntry] { entries.filter { $0.parentID == parentID } }
    var folders: [BrowserFavoriteEntry] { entries.filter { $0.kind == .folder } }

    @discardableResult
    func addPage(url: URL, title: String, in parentID: UUID? = nil) -> UUID? {
        guard let url = BrowserSearchEngine.websiteURL(url), validParent(parentID) else { return nil }
        if let existing = entries.first(where: { $0.kind == .page && $0.url == url }) { return existing.id }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = BrowserFavoriteEntry(kind: .page, title: title.isEmpty ? url.host ?? "Page" : String(title.prefix(200)), url: url, parentID: parentID)
        entries.append(item)
        persist()
        return item.id
    }

    @discardableResult
    func createFolder(title: String, in parentID: UUID? = nil) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, validParent(parentID) else { return nil }
        let item = BrowserFavoriteEntry(kind: .folder, title: String(title.prefix(200)), parentID: parentID)
        entries.append(item)
        persist()
        return item.id
    }

    func rename(_ id: UUID, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].title = String(title.prefix(200))
        persist()
    }

    func canMove(_ id: UUID, into parentID: UUID?) -> Bool {
        guard entry(id) != nil, validParent(parentID) else { return false }
        var parent = parentID
        var seen: Set<UUID> = [id]
        while let current = parent {
            guard seen.insert(current).inserted else { return false }
            parent = entry(current)?.parentID
        }
        return true
    }

    @discardableResult
    func move(_ id: UUID, into parentID: UUID?) -> Bool {
        guard canMove(id, into: parentID), let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].parentID = parentID
        persist()
        return true
    }

    func setCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.kind == .folder }) else { return }
        entries[index].isCollapsed = collapsed
        persist()
    }

    /// Removing a folder keeps its contents in the nearest remaining parent.
    func remove(_ ids: Set<UUID>) {
        let previous = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries.removeAll { ids.contains($0.id) }
        for index in entries.indices {
            var parent = entries[index].parentID
            var visited = Set<UUID>()
            while let id = parent, ids.contains(id), visited.insert(id).inserted { parent = previous[id]?.parentID }
            entries[index].parentID = parent
        }
        persist()
    }

    func reorder(in parentID: UUID?, from offsets: IndexSet, to destination: Int) {
        let siblings = children(in: parentID)
        guard offsets.allSatisfy({ siblings.indices.contains($0) }), (0...siblings.count).contains(destination) else { return }
        let moving = offsets.sorted().map { siblings[$0] }
        var reordered = siblings.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        var iterator = reordered.makeIterator()
        for index in entries.indices where entries[index].parentID == parentID {
            if let next = iterator.next() { entries[index] = next }
        }
        persist()
    }

    func folderPath(_ id: UUID) -> String {
        var titles: [String] = []
        var current = entry(id)
        var visited = Set<UUID>()
        while let item = current, visited.insert(item.id).inserted {
            titles.append(item.title)
            current = item.parentID.flatMap(entry)
        }
        return titles.reversed().joined(separator: " / ")
    }

    private func validParent(_ id: UUID?) -> Bool { id == nil || id.flatMap(entry)?.kind == .folder }
    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.storageKey) }
    }
}
