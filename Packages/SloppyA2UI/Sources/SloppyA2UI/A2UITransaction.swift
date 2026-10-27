import Foundation

/// A bounded, atomic batch for one surface. Incomplete intermediate trees are never published.
public struct A2UITransaction: Sendable {
    public struct Failure: Error, Sendable {
        public let path: String
        public let reason: String
    }
    private enum Operation: Sendable {
        case create(String), components([A2UIComponent]), model(String, A2UIValue?), delete
    }
    public let surfaceId: String
    private let operations: [Operation]

    public init(json: String) throws {
        guard json.utf8.count <= 65_536 else { throw Failure(path: "messages", reason: "Batch exceeds 64 KiB") }
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) } catch {
            throw Failure(path: "messages", reason: "Invalid JSON")
        }
        guard let frames = parsed as? [[String: Any]],
            (1...32).contains(frames.count)
        else {
            throw Failure(path: "messages", reason: "Expected 1–32 envelopes within 64 KiB")
        }
        let names: Set<String> = ["createSurface", "updateComponents", "updateDataModel", "deleteSurface"]
        var id: String?
        var operations: [Operation] = []
        for (index, frame) in frames.enumerated() {
            let path = "messages[\(index)]"
            guard frame["version"] as? String == "v0.9.1",
                let name = names.intersection(frame.keys).first,
                Set(frame.keys) == ["version", name], let body = frame[name] as? [String: Any],
                let target = body["surfaceId"] as? String, id == nil || id == target
            else {
                throw Failure(path: path, reason: "Expected one v0.9.1 operation for the same surface")
            }
            id = target
            let allowed: Set<String>
            switch name {
            case "createSurface": allowed = ["surfaceId", "catalogId"]
            case "updateComponents": allowed = ["surfaceId", "components"]
            case "updateDataModel": allowed = ["surfaceId", "path", "value"]
            default: allowed = ["surfaceId"]
            }
            guard Set(body.keys).isSubset(of: allowed) else {
                throw Failure(path: path, reason: "Unsupported operation properties")
            }
            do {
                switch name {
                case "createSurface":
                    guard let catalog = body["catalogId"] as? String else { throw Failure(path: path, reason: "Missing catalogId") }
                    operations.append(.create(catalog))
                case "updateComponents":
                    guard let list = body["components"] as? [[String: Any]], (1...128).contains(list.count),
                        list.allSatisfy({ Set($0.keys).isSubset(of: ["id", "component", "text", "children"]) })
                    else {
                        throw Failure(path: path + ".updateComponents.components", reason: "Unsupported components")
                    }
                    let components = try Self.decode([A2UIComponent].self, list)
                    guard Set(components.map(\.id)).count == components.count else {
                        throw Failure(path: path, reason: "Duplicate component IDs")
                    }
                    operations.append(.components(components))
                case "updateDataModel":
                    let pointer = try body["path"].map { try Self.decode(String.self, $0) } ?? "/"
                    let value = try body["value"].map { try Self.decode(A2UIValue.self, $0) }
                    operations.append(.model(pointer, value))
                default: operations.append(.delete)
                }
            } catch let error as Failure { throw error } catch { throw Failure(path: path, reason: "Invalid operation payload") }
        }
        surfaceId = id ?? ""
        self.operations = operations
    }

    public func applying(to previous: A2UISurfaceSnapshot?, fallbackText: String) throws -> A2UISurfaceSnapshot {
        guard previous?.surfaceId == nil || previous?.surfaceId == surfaceId,
            (previous?.revision ?? 0) < Int.max
        else { throw Failure(path: "surfaceId", reason: "Invalid previous state") }
        var surface = previous ?? .init(surfaceId: surfaceId, revision: 1, fallbackText: fallbackText, components: [])
        var exists = previous != nil && previous?.isDeleted != true
        for operation in operations {
            switch operation {
            case .create(let catalog):
                guard !exists, catalog == A2UISurfaceSnapshot.supportedCatalogID else {
                    throw Failure(path: "createSurface", reason: "Surface exists or catalog is unsupported")
                }
                surface.components = []; surface.dataModel = .object([:]); surface.isDeleted = nil; exists = true
            case .components(let changes):
                guard exists else { throw Failure(path: "updateComponents", reason: "Create the surface first") }
                for item in changes {
                    if let index = surface.components.firstIndex(where: { $0.id == item.id }) {
                        surface.components[index] = item
                    } else {
                        surface.components.append(item)
                    }
                }
            case .model(let path, let value):
                guard exists, path.utf8.count <= 1_024, path.isEmpty || path.hasPrefix("/") else {
                    throw Failure(path: "updateDataModel.path", reason: "Invalid surface or JSON Pointer")
                }
                let tokens = path.isEmpty || path == "/" ? [] : String(path.dropFirst()).components(separatedBy: "/")
                guard tokens.count <= 16, tokens.allSatisfy({ $0.range(of: "~(?![01])", options: .regularExpression) == nil }) else {
                    throw Failure(path: "updateDataModel.path", reason: "Invalid JSON Pointer escape or depth")
                }
                let decoded = tokens.map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
                surface.dataModel = try (surface.dataModel ?? .object([:])).replacing(decoded[...], with: value)
            case .delete:
                guard exists else { throw Failure(path: "deleteSurface", reason: "Surface does not exist") }
                surface.components = []; surface.dataModel = nil; surface.isDeleted = true; exists = false
            }
        }
        surface.revision = (previous?.revision ?? 0) + 1
        surface.fallbackText = fallbackText
        do { try surface.validate() } catch { throw Failure(path: "surface", reason: String(describing: error)) }
        return surface
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
    }
}
