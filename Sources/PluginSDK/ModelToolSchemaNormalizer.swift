import AnyLanguageModel
import Foundation

public enum ModelToolSchemaNormalizer {
    public static func providerSafeObjectSchema(_ schema: GenerationSchema) -> [String: Any] {
        let fallback: [String: Any] = ["type": "object"]
        guard let data = try? JSONEncoder().encode(schema),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }

        guard var resolved = resolveRefs(in: json) as? [String: Any] else {
            return fallback
        }
        resolved.removeValue(forKey: "$defs")
        resolved.removeValue(forKey: "$ref")
        if resolved["type"] as? String != "object" {
            resolved["type"] = "object"
        }
        return resolved
    }

    private static func resolveRefs(in value: Any, root: [String: Any]? = nil) -> Any {
        if let array = value as? [Any] {
            return array.map { resolveRefs(in: $0, root: root) }
        }

        guard var object = value as? [String: Any] else {
            return value
        }

        let documentRoot = root ?? object
        if let ref = object["$ref"] as? String,
           let resolved = resolveLocalRef(ref, root: documentRoot) {
            object.removeValue(forKey: "$ref")
            object.removeValue(forKey: "$defs")
            var merged = resolved
            for (key, value) in object where key != "$ref" && key != "$defs" {
                merged[key] = value
            }
            return resolveRefs(in: merged, root: documentRoot)
        }

        object.removeValue(forKey: "$defs")
        for (key, value) in object {
            object[key] = resolveRefs(in: value, root: documentRoot)
        }
        return object
    }

    private static func resolveLocalRef(_ ref: String, root: [String: Any]) -> [String: Any]? {
        guard ref.hasPrefix("#/") else { return nil }
        let path = ref
            .dropFirst(2)
            .split(separator: "/")
            .map { String($0).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }

        var current: Any = root
        for component in path {
            guard let object = current as? [String: Any],
                  let next = object[component] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }
}
